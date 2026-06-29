import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Session index repair")
struct SessionRepairTests {
    @Test("dry run reports missing, orphan and duplicate index entries")
    func dryRunReportsIndexProblems() throws {
        let root = try TemporaryDirectory()
        let sessions = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try session("s1", title: "First", timestamp: "2026-06-29T01:00:00Z")
            .write(to: sessions.appending(path: "rollout-s1.jsonl"), atomically: true, encoding: .utf8)
        try session("s2", title: "Second", timestamp: "2026-06-29T02:00:00Z")
            .write(to: sessions.appending(path: "rollout-s2.jsonl"), atomically: true, encoding: .utf8)
        try """
        {"id":"s1","thread_name":"First","updated_at":"2026-06-29T01:00:00Z"}
        {"id":"s1","thread_name":"First copy","updated_at":"2026-06-29T01:00:00Z"}
        {"id":"old","thread_name":"Gone","updated_at":"2026-06-28T01:00:00Z"}
        """.write(to: root.url.appending(path: "session_index.jsonl"), atomically: true, encoding: .utf8)

        let service = SessionRepairService(codexHome: root.url)
        let report = try service.dryRun()

        #expect(report.missingIndexIDs == ["s2"])
        #expect(report.orphanIndexIDs == ["old"])
        #expect(report.duplicateIndexIDs == ["s1"])
        #expect(FileManager.default.fileExists(atPath: root.url.appending(path: "session_index.jsonl").path))
    }

    @Test("repair backs up and rewrites index")
    func repairBacksUpAndRewritesIndex() throws {
        let root = try TemporaryDirectory()
        let sessions = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try session("s1", title: "First", timestamp: "2026-06-29T01:00:00Z")
            .write(to: sessions.appending(path: "rollout-s1.jsonl"), atomically: true, encoding: .utf8)
        try #"{"id":"old","thread_name":"Gone","updated_at":"2026-06-28T01:00:00Z"}"#
            .write(to: root.url.appending(path: "session_index.jsonl"), atomically: true, encoding: .utf8)

        let result = try SessionRepairService(codexHome: root.url).repair()
        let repaired = try String(contentsOf: root.url.appending(path: "session_index.jsonl"))

        #expect(FileManager.default.fileExists(atPath: result.backupPath!.path))
        #expect(repaired.contains(#""id":"s1""#))
        #expect(repaired.contains(#""id":"old""#) == false)
    }

    @Test("dry run only needs valid session head and tail")
    func dryRunDoesNotRequireWholeFileTextDecode() throws {
        let root = try TemporaryDirectory()
        let sessions = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        var data = Data()
        data.append(#"{"timestamp":"2026-06-29T01:00:00Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}"#.data(using: .utf8)!)
        data.append(Data("\n".utf8))
        data.append(Data([0xff, 0xfe, 0xfd]))
        data.append(Data("\n".utf8))
        data.append(#"{"timestamp":"2026-06-29T01:01:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Tail title"}]}}"#.data(using: .utf8)!)
        try data.write(to: sessions.appending(path: "rollout-s1.jsonl"))

        let report = try SessionRepairService(codexHome: root.url).dryRun()

        #expect(report.plannedEntries == 1)
    }

    private func session(_ id: String, title: String, timestamp: String) -> String {
        """
        {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(id)","cwd":"/tmp"}}
        {"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\(title)"}]}}
        """
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
