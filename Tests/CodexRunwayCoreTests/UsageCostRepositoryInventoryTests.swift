import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Usage cost repository — source inventory")
struct UsageCostRepositoryInventoryTests {
    @Test("archive move is adopted and an identical copy is counted once")
    func archiveMoveAndIdenticalCopyAreDeduplicated() async throws {
        let fixture = try RepositoryFixture()
        let contents = tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 100) + "\n"
        let original = try fixture.write(contents, basename: "rollout-move.jsonl")
        let identity = try fileIdentity(original)
        let repository = fixture.repository()
        let request = fullWindowQuery()
        _ = try await repository.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let beforeMove = await repository.diagnosticsSnapshot()

        let archived = try fixture.archivedURL(basename: original.lastPathComponent)
        try FileManager.default.moveItem(at: original, to: archived)
        #expect(try fileIdentity(archived) == identity)
        let moved = try await repository.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let afterMove = await repository.diagnosticsSnapshot()

        #expect(moved[request.id]?.totals.turns == 1)
        #expect(afterMove.bytesRead == beforeMove.bytesRead)
        #expect(afterMove.adoptedFiles == beforeMove.adoptedFiles + 1)

        let copied = try fixture.sessionURL(basename: archived.lastPathComponent)
        try FileManager.default.copyItem(at: archived, to: copied)
        #expect(try fileIdentity(copied) != identity)
        let deduplicated = try await repository.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let afterCopy = await repository.diagnosticsSnapshot()

        #expect(deduplicated[request.id]?.totals.turns == 1)
        #expect(afterCopy.duplicateFiles == afterMove.duplicateFiles + 1)

        let restarted = fixture.repository()
        let persistedWarm = try await restarted.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let persistedDiagnostics = await restarted.diagnosticsSnapshot()
        #expect(persistedWarm[request.id]?.totals.turns == 1)
        #expect(persistedDiagnostics.bytesRead == 0)
        #expect(persistedDiagnostics.validationBytesRead == 0)

        try FileManager.default.removeItem(at: archived)
        let adoptedCopy = try await restarted.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let afterAdoption = await restarted.diagnosticsSnapshot()
        #expect(adoptedCopy[request.id]?.totals.turns == 1)
        #expect(afterAdoption.adoptedFiles == persistedDiagnostics.adoptedFiles + 1)
        #expect(afterAdoption.rebuiltFiles == persistedDiagnostics.rebuiltFiles)
        #expect(afterAdoption.bytesRead == persistedDiagnostics.bytesRead)
        #expect(afterAdoption.validationBytesRead == persistedDiagnostics.validationBytesRead)
    }

    @Test("same-size rewrite followed by a move rebuilds stale events")
    func rewrittenMoveIsNotBlindlyAdopted() async throws {
        let fixture = try RepositoryFixture()
        let prefix = #"{"type":"event_msg","payload":{"type":"message","content":""#
            + String(repeating: "p", count: 20 * 1_024) + #""}}"# + "\n"
        let suffix = #"{"type":"event_msg","payload":{"type":"message","content":""#
            + String(repeating: "s", count: 20 * 1_024) + #""}}"# + "\n"
        let originalText = prefix
            + tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 100) + "\n"
            + suffix
        let changedText = prefix
            + tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 900) + "\n"
            + suffix
        #expect(originalText.utf8.count == changedText.utf8.count)
        let original = try fixture.write(originalText, basename: "rollout-rewritten-move.jsonl")
        let originalMTime = try #require(
            original.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let repository = fixture.repository()
        let request = fullWindowQuery()
        _ = try await repository.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let before = await repository.diagnosticsSnapshot()

        try replacePreservingIdentity(changedText, at: original)
        try FileManager.default.setAttributes(
            [.modificationDate: originalMTime],
            ofItemAtPath: original.path)
        let archived = try fixture.archivedURL(basename: original.lastPathComponent)
        try FileManager.default.moveItem(at: original, to: archived)
        let summary = try await repository.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let after = await repository.diagnosticsSnapshot()

        #expect(summary[request.id]?.totals.totalTokens == 905)
        #expect(after.rebuiltFiles == before.rebuiltFiles + 1)
        #expect(after.adoptedFiles == before.adoptedFiles)
    }

    @Test("duplicate hash cache invalidates a modified copy")
    func changedDuplicateStillReportsConflict() async throws {
        let fixture = try RepositoryFixture()
        let originalText = tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 100) + "\n"
        let changedText = tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 900) + "\n"
        #expect(originalText.utf8.count == changedText.utf8.count)
        let original = try fixture.write(originalText, basename: "rollout-cached-conflict.jsonl")
        let copy = try fixture.archivedURL(basename: original.lastPathComponent)
        try FileManager.default.copyItem(at: original, to: copy)
        let repository = fixture.repository()
        let request = fullWindowQuery()
        _ = try await repository.summaries(
            for: [request], calculatedAt: fixedNow, policy: .ifChanged)
        let before = await repository.diagnosticsSnapshot()

        try replacePreservingIdentity(changedText, at: copy)
        do {
            _ = try await repository.summaries(
                for: [request], calculatedAt: fixedNow, policy: .ifChanged)
            Issue.record("Expected modified duplicate conflict")
        } catch UsageCostRepositoryError.duplicateConflict(let basename) {
            #expect(basename == original.lastPathComponent)
        }
        let after = await repository.diagnosticsSnapshot()

        #expect(after.validationBytesRead - before.validationBytesRead == changedText.utf8.count)
    }

    @Test("divergent duplicate basenames fail with a sanitized typed error")
    func divergentDuplicateFailsExplicitly() async throws {
        let fixture = try RepositoryFixture()
        let basename = "rollout-conflict.jsonl"
        try fixture.write(
            tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 100) + "\n",
            basename: basename)
        let archived = try fixture.archivedURL(basename: basename)
        try Data((tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 900) + "\n").utf8)
            .write(to: archived)
        let repository = fixture.repository()

        do {
            _ = try await repository.summaries(
                for: [fullWindowQuery()], calculatedAt: fixedNow, policy: .ifChanged)
            Issue.record("Expected a duplicate conflict")
        } catch UsageCostRepositoryError.duplicateConflict(let conflictingBasename) {
            #expect(conflictingBasename == basename)
        } catch {
            Issue.record("Expected UsageCostRepositoryError.duplicateConflict, got \(error)")
        }
    }

    @Test("source inventory does not follow JSONL symbolic links")
    func symbolicLinksAreNotIndexed() async throws {
        let fixture = try RepositoryFixture()
        let outside = fixture.root.appending(path: "outside.jsonl")
        try Data((tokenLine(timestamp: "2026-06-29T01:00:00Z", input: 100) + "\n").utf8)
            .write(to: outside)
        let link = try fixture.sessionURL(basename: "rollout-link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let repository = fixture.repository()

        let summaries = try await repository.summaries(
            for: [fullWindowQuery()], calculatedAt: fixedNow, policy: .ifChanged)
        let diagnostics = await repository.diagnosticsSnapshot()

        #expect(summaries["full"]?.source == .unavailable)
        #expect(diagnostics.bytesRead == 0)
        #expect(diagnostics.rebuiltFiles == 0)
    }
}
