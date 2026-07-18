import Darwin
import Foundation

struct UsageCostLogRecord: Sendable {
    var timestamp: Date
    var utcDay: String
    var model: String?
    var contextModel: String?
    var sessionCWD: String?
    var lastTokenUsage: TokenUsage?
}

struct UsageCostParsedLine: Sendable {
    var byteOffset: UInt64
    var isLFComplete: Bool
    var record: UsageCostLogRecord
}

struct UsageCostLogStreamResult: Equatable, Sendable {
    var snapshotSize: UInt64
    var snapshotDevice: Int64
    var snapshotInode: Int64
    var snapshotBirthNanoseconds: Int64
    var snapshotModificationNanoseconds: Int64
    var snapshotStatusChangeNanoseconds: Int64
    var bytesRead: Int
    var candidateLines: Int
    var decodedLines: Int
    var malformedCandidateLines: Int
    var incompleteMalformedCandidateLines: Int
    var oversizedLines: Int
    var incompleteOversizedLines: Int
    var maxBufferedBytes: Int
    var lastCompleteOffset: UInt64
    var trailingLineStartOffset: UInt64?
}

struct UsageCostLogStream {
    static let chunkSize = 256 * 1_024
    static let maximumLineBytes = 8 * 1_024 * 1_024

    private let reader: UsageCostLogReader
    private let parser = UsageCostLogParser()

    init(
        chunkSize: Int = UsageCostLogStream.chunkSize,
        maximumLineBytes: Int = UsageCostLogStream.maximumLineBytes)
    {
        reader = UsageCostLogReader(chunkSize: chunkSize, maximumLineBytes: maximumLineBytes)
    }

    func read(
        file: URL,
        fromOffset: UInt64 = 0,
        expectedSource: UsageCostSourceFile? = nil,
        onRecord: (UsageCostParsedLine) throws -> Void) throws -> UsageCostLogStreamResult
    {
        var decodedLines = 0
        var malformedLines = 0
        var incompleteMalformedLines = 0
        let result = try reader.read(
            file: file,
            fromOffset: fromOffset,
            expectedSource: expectedSource) { line in
            let record: UsageCostLogRecord
            do {
                record = try autoreleasepool { try parser.parse(line.data) }
            } catch {
                malformedLines += 1
                if !line.isLFComplete { incompleteMalformedLines += 1 }
                return
            }
            decodedLines += 1
            try onRecord(UsageCostParsedLine(
                byteOffset: line.byteOffset,
                isLFComplete: line.isLFComplete,
                record: record))
        }
        return UsageCostLogStreamResult(
            snapshotSize: result.snapshotSize,
            snapshotDevice: result.snapshotDevice,
            snapshotInode: result.snapshotInode,
            snapshotBirthNanoseconds: result.snapshotBirthNanoseconds,
            snapshotModificationNanoseconds: result.snapshotModificationNanoseconds,
            snapshotStatusChangeNanoseconds: result.snapshotStatusChangeNanoseconds,
            bytesRead: result.bytesRead,
            candidateLines: result.candidateLines,
            decodedLines: decodedLines,
            malformedCandidateLines: malformedLines,
            incompleteMalformedCandidateLines: incompleteMalformedLines,
            oversizedLines: result.oversizedLines,
            incompleteOversizedLines: result.incompleteOversizedLines,
            maxBufferedBytes: result.maxBufferedBytes,
            lastCompleteOffset: result.lastCompleteOffset,
            trailingLineStartOffset: result.trailingLineStartOffset)
    }

}

private struct UsageCostCandidateLine {
    var byteOffset: UInt64
    var isLFComplete: Bool
    var data: Data
}

private struct UsageCostLogReadResult {
    var snapshotSize: UInt64
    var snapshotDevice: Int64
    var snapshotInode: Int64
    var snapshotBirthNanoseconds: Int64
    var snapshotModificationNanoseconds: Int64
    var snapshotStatusChangeNanoseconds: Int64
    var bytesRead = 0
    var candidateLines = 0
    var oversizedLines = 0
    var incompleteOversizedLines = 0
    var maxBufferedBytes = 0
    var lastCompleteOffset: UInt64
    var trailingLineStartOffset: UInt64?
}

private enum UsageCostLogReaderError: Error {
    case offsetBeyondSnapshot(offset: UInt64, snapshotSize: UInt64)
    case unexpectedEndOfFile(expected: UInt64, actual: UInt64)
    case invalidSourceFile
    case sourceIdentityChanged
    case fileStatus(code: Int32)
}

private struct UsageCostLogReader {
    var chunkSize: Int
    var maximumLineBytes: Int

    func read(
        file: URL,
        fromOffset: UInt64,
        expectedSource: UsageCostSourceFile?,
        onCandidate: (UsageCostCandidateLine) throws -> Void) throws -> UsageCostLogReadResult
    {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var metadata = stat()
        guard Darwin.fstat(handle.fileDescriptor, &metadata) == 0 else {
            throw UsageCostLogReaderError.fileStatus(code: errno)
        }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size >= 0 else {
            throw UsageCostLogReaderError.invalidSourceFile
        }
        if let expectedSource {
            guard Int64(metadata.st_dev) == expectedSource.device,
                  Int64(bitPattern: UInt64(metadata.st_ino)) == expectedSource.inode,
                  try nanoseconds(metadata.st_birthtimespec) == expectedSource.birthNanoseconds
            else { throw UsageCostLogReaderError.sourceIdentityChanged }
        }
        let snapshotSize = UInt64(metadata.st_size)
        guard fromOffset <= snapshotSize else {
            throw UsageCostLogReaderError.offsetBeyondSnapshot(
                offset: fromOffset,
                snapshotSize: snapshotSize)
        }
        try handle.seek(toOffset: fromOffset)

        var accumulator = LineAccumulator(
            lineStartOffset: fromOffset,
            maximumLineBytes: maximumLineBytes)
        var position = fromOffset
        var bytesRead = 0
        var maxBufferedBytes = 0
        while position < snapshotSize {
            try Task.checkCancellation()
            let remaining = snapshotSize - position
            let requestedBytes = min(chunkSize, Int(remaining))
            let consumed = try autoreleasepool { () throws -> Int in
                let chunk = try handle.read(upToCount: requestedBytes) ?? Data()
                guard !chunk.isEmpty else {
                    throw UsageCostLogReaderError.unexpectedEndOfFile(
                        expected: snapshotSize,
                        actual: position)
                }
                maxBufferedBytes = max(maxBufferedBytes, chunk.count)
                try accumulator.consume(chunk: chunk, at: position, onCandidate: onCandidate)
                maxBufferedBytes = max(maxBufferedBytes, accumulator.maxBufferedBytes)
                return chunk.count
            }
            position += UInt64(consumed)
            bytesRead += consumed
        }
        try accumulator.finish(onCandidate: onCandidate)
        maxBufferedBytes = max(maxBufferedBytes, accumulator.maxBufferedBytes)
        return UsageCostLogReadResult(
            snapshotSize: snapshotSize,
            snapshotDevice: Int64(metadata.st_dev),
            snapshotInode: Int64(bitPattern: UInt64(metadata.st_ino)),
            snapshotBirthNanoseconds: try nanoseconds(metadata.st_birthtimespec),
            snapshotModificationNanoseconds: try nanoseconds(metadata.st_mtimespec),
            snapshotStatusChangeNanoseconds: try nanoseconds(metadata.st_ctimespec),
            bytesRead: bytesRead,
            candidateLines: accumulator.candidateLines,
            oversizedLines: accumulator.oversizedLines,
            incompleteOversizedLines: accumulator.discardingOversizedLine ? 1 : 0,
            maxBufferedBytes: maxBufferedBytes,
            lastCompleteOffset: accumulator.lastCompleteOffset,
            trailingLineStartOffset: accumulator.lastCompleteOffset < snapshotSize
                ? accumulator.lastCompleteOffset
                : nil)
    }
}

private struct LineAccumulator {
    var lineStartOffset: UInt64
    var maximumLineBytes: Int
    var buffer = Data()
    var discardingOversizedLine = false
    var candidateLines = 0
    var oversizedLines = 0
    var maxBufferedBytes = 0
    var lastCompleteOffset: UInt64

    init(lineStartOffset: UInt64, maximumLineBytes: Int) {
        self.lineStartOffset = lineStartOffset
        self.maximumLineBytes = maximumLineBytes
        self.lastCompleteOffset = lineStartOffset
    }

    mutating func consume(
        chunk: Data,
        at chunkOffset: UInt64,
        onCandidate: (UsageCostCandidateLine) throws -> Void) throws
    {
        var segmentStart = chunk.startIndex
        while let newline = chunk[segmentStart...].firstIndex(of: 0x0A) {
            try consume(
                segment: chunk[segmentStart..<newline],
                isLFComplete: true,
                onCandidate: onCandidate)
            let afterNewline = chunk.index(after: newline)
            lineStartOffset = chunkOffset + UInt64(afterNewline - chunk.startIndex)
            lastCompleteOffset = lineStartOffset
            segmentStart = afterNewline
        }
        if segmentStart < chunk.endIndex {
            try consume(
                segment: chunk[segmentStart..<chunk.endIndex],
                isLFComplete: false,
                onCandidate: onCandidate)
        }
    }

    mutating func finish(onCandidate: (UsageCostCandidateLine) throws -> Void) throws {
        guard !discardingOversizedLine, !buffer.isEmpty else { return }
        try emit(buffer, isLFComplete: false, onCandidate: onCandidate)
        buffer = Data()
    }

    private mutating func consume(
        segment: Data.SubSequence,
        isLFComplete: Bool,
        onCandidate: (UsageCostCandidateLine) throws -> Void) throws
    {
        guard !discardingOversizedLine else {
            if isLFComplete { discardingOversizedLine = false }
            return
        }
        guard buffer.count + segment.count <= maximumLineBytes else {
            oversizedLines += 1
            buffer = Data()
            discardingOversizedLine = !isLFComplete
            return
        }
        if buffer.isEmpty, isLFComplete {
            try emit(segment, isLFComplete: true, onCandidate: onCandidate)
            return
        }
        buffer.append(contentsOf: segment)
        maxBufferedBytes = max(maxBufferedBytes, buffer.count)
        guard isLFComplete else { return }
        try emit(buffer, isLFComplete: true, onCandidate: onCandidate)
        buffer = Data()
    }

    private mutating func emit(
        _ bytes: Data.SubSequence,
        isLFComplete: Bool,
        onCandidate: (UsageCostCandidateLine) throws -> Void) throws
    {
        guard UsageCostLinePrefilter.isCandidate(bytes) else { return }
        candidateLines += 1
        var data = Data(bytes)
        if data.last == 0x0D { data.removeLast() }
        try onCandidate(UsageCostCandidateLine(
            byteOffset: lineStartOffset,
            isLFComplete: isLFComplete,
            data: data))
    }
}

private enum UsageCostLinePrefilter {
    private static let markers = [
        Data("token_count".utf8),
        Data("turn_context".utf8),
        Data("session_meta".utf8),
        Data("\"cwd\"".utf8),
    ]

    static func isCandidate(_ bytes: Data.SubSequence) -> Bool {
        markers.contains { bytes.range(of: $0) != nil }
    }
}

private func nanoseconds(_ time: timespec) throws -> Int64 {
    let (seconds, multipliedOverflow) = Int64(time.tv_sec)
        .multipliedReportingOverflow(by: 1_000_000_000)
    let (result, addedOverflow) = seconds.addingReportingOverflow(Int64(time.tv_nsec))
    guard !multipliedOverflow, !addedOverflow else {
        throw UsageCostLogReaderError.invalidSourceFile
    }
    return result
}
