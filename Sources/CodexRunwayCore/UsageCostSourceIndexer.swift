import CryptoKit
import Foundation

struct UsageCostSourceIndexer {
    static let hashWindowBytes: UInt64 = 16 * 1_024
    private static let emptyHash = Data(SHA256.hash(data: Data()))

    let store: UsageCostIndexStore
    let parserVersion: Int
    private let stream = UsageCostLogStream()

    func rebuild(
        file: UsageCostSourceFile,
        existing: UsageCostIndexedSource?,
        knownFullHash: Data?,
        diagnostics: inout UsageCostRepositoryDiagnostics
    ) throws -> UsageCostScanAnomalies {
        let initial = initialSource(file: file, id: existing?.id)
        var metrics: ScanMetrics?
        _ = try store.rebuildOrAppend(
            initialSource: initial,
            replacingEventsFrom: 0
        ) { emit in
            let scanned = try scan(
                file: file,
                fromOffset: 0,
                model: "unknown-model",
                project: SessionProjectName.unknown,
                existing: nil,
                knownFullHash: knownFullHash,
                emit: emit)
            metrics = scanned.metrics
            return scanned.source
        }
        guard let metrics else { return .zero }
        diagnostics.record(metrics)
        diagnostics.rebuiltFiles += 1
        return metrics.provisionalAnomalies
    }

    func append(
        file: UsageCostSourceFile,
        existing: UsageCostIndexedSource,
        diagnostics: inout UsageCostRepositoryDiagnostics
    ) throws -> UsageCostScanAnomalies {
        var initial = existing
        initial.applyMetadata(from: file)
        var metrics: ScanMetrics?
        _ = try store.rebuildOrAppend(
            initialSource: initial,
            replacingEventsFrom: existing.completeOffset
        ) { emit in
            let scanned = try scan(
                file: file,
                fromOffset: existing.completeOffset,
                model: existing.currentModel,
                project: existing.currentProject,
                existing: existing,
                knownFullHash: nil,
                emit: emit)
            metrics = scanned.metrics
            return scanned.source
        }
        guard let metrics else { return .zero }
        diagnostics.record(metrics)
        diagnostics.appendedFiles += 1
        return metrics.provisionalAnomalies
    }

    func adopt(
        file: UsageCostSourceFile,
        existing: UsageCostIndexedSource,
        fullHash: Data?
    ) throws {
        var adopted = existing
        adopted.applyMetadata(from: file)
        if let fullHash { adopted.fullHash = fullHash }
        try store.adoptSource(adopted)
    }

    func canAppend(
        file: UsageCostSourceFile,
        existing: UsageCostIndexedSource,
        diagnostics: inout UsageCostRepositoryDiagnostics
    ) throws -> Bool {
        guard existing.completeOffset <= file.size,
              existing.firstHashLength >= 0,
              existing.checkpointHashLength >= 0,
              UInt64(existing.firstHashLength) <= file.size,
              UInt64(existing.checkpointHashLength) <= existing.completeOffset
        else { return false }
        let first = try validate(
            file,
            range: 0..<UInt64(existing.firstHashLength),
            expected: existing.firstHash,
            diagnostics: &diagnostics)
        guard first else { return false }
        let checkpointLength = UInt64(existing.checkpointHashLength)
        return try validate(
            file,
            range: (existing.completeOffset - checkpointLength)..<existing.completeOffset,
            expected: existing.checkpointHash,
            diagnostics: &diagnostics)
    }

    private func validate(
        _ file: UsageCostSourceFile,
        range: Range<UInt64>,
        expected: Data,
        diagnostics: inout UsageCostRepositoryDiagnostics
    ) throws -> Bool {
        let hash = try UsageCostFileHasher.sha256(of: file, range: range)
        diagnostics.validationBytesRead += hash.bytesRead
        return hash.digest == expected
    }

    private func scan(
        file: UsageCostSourceFile,
        fromOffset: UInt64,
        model: String,
        project: String,
        existing: UsageCostIndexedSource?,
        knownFullHash: Data?,
        emit: UsageCostIndexStore.EventEmitter
    ) throws -> (source: UsageCostIndexedSource, metrics: ScanMetrics) {
        var currentModel = model
        var currentProject = project
        var checkpointModel = model
        var checkpointProject = project
        let result = try stream.read(
            file: file.url,
            fromOffset: fromOffset,
            expectedSource: file) { line in
            let record = line.record
            if let cwd = record.sessionCWD {
                currentProject = SessionProjectName.displayName(for: cwd)
            }
            if let contextModel = record.contextModel { currentModel = contextModel }
            if let usage = record.lastTokenUsage {
                let cached = max(0, usage.cachedInputTokens)
                let uncached = usage.inputTokens >= cached
                    ? usage.inputTokens - cached
                    : 0
                try emit(UsageCostIndexedEvent(
                    fileID: existing?.id,
                    byteOffset: line.byteOffset,
                    timestamp: record.timestamp,
                    utcDay: record.utcDay,
                    model: record.model ?? currentModel,
                    project: currentProject,
                    uncachedInputTokens: uncached,
                    cachedInputTokens: cached,
                    outputTokens: max(0, usage.outputTokens)))
            }
            if line.isLFComplete {
                checkpointModel = currentModel
                checkpointProject = currentProject
            }
        }
        let hashes = try hashes(
            file: file,
            snapshotSize: result.snapshotSize,
            completeOffset: result.lastCompleteOffset,
            existing: existing)
        var source = initialSource(file: file, id: existing?.id)
        source.device = result.snapshotDevice
        source.inode = result.snapshotInode
        source.birthTimeNanoseconds = result.snapshotBirthNanoseconds
        source.modificationTimeNanoseconds = result.snapshotModificationNanoseconds
        source.statusChangeTimeNanoseconds = result.snapshotStatusChangeNanoseconds
        source.size = result.snapshotSize
        source.completeOffset = result.lastCompleteOffset
        source.currentModel = checkpointModel
        source.currentProject = checkpointProject
        source.firstHash = hashes.first.digest
        source.firstHashLength = hashes.first.length
        source.checkpointHash = hashes.checkpoint.digest
        source.checkpointHashLength = hashes.checkpoint.length
        source.malformedLines = (existing?.malformedLines ?? 0)
            + result.malformedCandidateLines - result.incompleteMalformedCandidateLines
        source.oversizedLines = (existing?.oversizedLines ?? 0)
            + result.oversizedLines - result.incompleteOversizedLines
        source.fullHash = knownFullHash.flatMap { file.size == result.snapshotSize ? $0 : nil }
            ?? result.fullHash
        let metrics = ScanMetrics(stream: result, hashBytes: hashes.bytesRead)
        return (source, metrics)
    }

    private func hashes(
        file: UsageCostSourceFile,
        snapshotSize: UInt64,
        completeOffset: UInt64,
        existing: UsageCostIndexedSource?
    ) throws -> (first: HashValue, checkpoint: HashValue, bytesRead: Int) {
        let firstLength = min(Self.hashWindowBytes, snapshotSize)
        let first: UsageCostFileHash
        if let existing, UInt64(existing.firstHashLength) == firstLength {
            first = UsageCostFileHash(digest: existing.firstHash, bytesRead: 0)
        } else {
            first = try UsageCostFileHasher.sha256(of: file, range: 0..<firstLength)
        }
        let checkpointLength = min(Self.hashWindowBytes, completeOffset)
        let checkpoint = try UsageCostFileHasher.sha256(
            of: file,
            range: (completeOffset - checkpointLength)..<completeOffset)
        return (
            HashValue(digest: first.digest, length: Int(firstLength)),
            HashValue(digest: checkpoint.digest, length: Int(checkpointLength)),
            first.bytesRead + checkpoint.bytesRead)
    }

    private func initialSource(file: UsageCostSourceFile, id: Int64?) -> UsageCostIndexedSource {
        UsageCostIndexedSource(
            id: id, basename: file.basename, root: file.root.rawValue, path: file.url.path,
            device: file.device, inode: file.inode, birthTimeNanoseconds: file.birthNanoseconds,
            modificationTimeNanoseconds: file.modificationNanoseconds,
            statusChangeTimeNanoseconds: file.statusChangeNanoseconds, size: file.size,
            completeOffset: 0, currentModel: "unknown-model",
            currentProject: SessionProjectName.unknown, firstHash: Self.emptyHash, firstHashLength: 0,
            checkpointHash: Self.emptyHash, checkpointHashLength: 0, parserVersion: parserVersion,
            malformedLines: 0, oversizedLines: 0, fullHash: nil)
    }
}

private struct HashValue {
    var digest: Data
    var length: Int
}

struct ScanMetrics {
    var bytesRead: Int
    var validationBytesRead: Int
    var candidateLines: Int
    var decodedLines: Int
    var malformedCandidateLines: Int
    var oversizedLines: Int
    var incompleteMalformedLines: Int
    var incompleteOversizedLines: Int
    var maxBufferedBytes: Int
    var hasIncompleteTail: Bool

    init(stream: UsageCostLogStreamResult, hashBytes: Int) {
        bytesRead = stream.bytesRead
        validationBytesRead = hashBytes
        candidateLines = stream.candidateLines
        decodedLines = stream.decodedLines
        malformedCandidateLines = stream.malformedCandidateLines
        oversizedLines = stream.oversizedLines
        incompleteMalformedLines = stream.incompleteMalformedCandidateLines
        incompleteOversizedLines = stream.incompleteOversizedLines
        maxBufferedBytes = stream.maxBufferedBytes
        hasIncompleteTail = stream.trailingLineStartOffset != nil
    }

    var provisionalAnomalies: UsageCostScanAnomalies {
        UsageCostScanAnomalies(
            malformedLines: incompleteMalformedLines,
            oversizedLines: incompleteOversizedLines)
    }
}

struct UsageCostScanAnomalies: Equatable {
    var malformedLines: Int
    var oversizedLines: Int

    static let zero = UsageCostScanAnomalies(malformedLines: 0, oversizedLines: 0)

    static func += (lhs: inout UsageCostScanAnomalies, rhs: UsageCostScanAnomalies) {
        lhs.malformedLines += rhs.malformedLines
        lhs.oversizedLines += rhs.oversizedLines
    }
}

private extension UsageCostIndexedSource {
    mutating func applyMetadata(from file: UsageCostSourceFile) {
        root = file.root.rawValue
        path = file.url.path
        device = file.device
        inode = file.inode
        birthTimeNanoseconds = file.birthNanoseconds
        modificationTimeNanoseconds = file.modificationNanoseconds
        statusChangeTimeNanoseconds = file.statusChangeNanoseconds
        size = file.size
    }
}

private extension UsageCostRepositoryDiagnostics {
    mutating func record(_ metrics: ScanMetrics) {
        bytesRead += metrics.bytesRead
        validationBytesRead += metrics.validationBytesRead
        candidateLines += metrics.candidateLines
        decodedLines += metrics.decodedLines
        malformedCandidateLines += metrics.malformedCandidateLines
        oversizedLines += metrics.oversizedLines
        maxBufferedBytes = max(maxBufferedBytes, metrics.maxBufferedBytes)
        if metrics.hasIncompleteTail { incompleteTailFiles += 1 }
    }
}
