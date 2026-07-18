import Foundation

struct UsageCostLogRecord: Sendable {
    var timestamp: Date
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
    var bytesRead: Int
    var candidateLines: Int
    var decodedLines: Int
    var malformedCandidateLines: Int
    var oversizedLines: Int
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
        onRecord: (UsageCostParsedLine) throws -> Void) throws -> UsageCostLogStreamResult
    {
        var decodedLines = 0
        var malformedLines = 0
        let result = try reader.read(file: file, fromOffset: fromOffset) { line in
            let record: UsageCostLogRecord
            do {
                record = try autoreleasepool { try parser.parse(line.data) }
            } catch {
                malformedLines += 1
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
            bytesRead: result.bytesRead,
            candidateLines: result.candidateLines,
            decodedLines: decodedLines,
            malformedCandidateLines: malformedLines,
            oversizedLines: result.oversizedLines,
            maxBufferedBytes: result.maxBufferedBytes,
            lastCompleteOffset: result.lastCompleteOffset,
            trailingLineStartOffset: result.trailingLineStartOffset)
    }

    func utcDay(for date: Date) -> String {
        parser.utcDay(for: date)
    }
}

private struct UsageCostCandidateLine {
    var byteOffset: UInt64
    var isLFComplete: Bool
    var data: Data
}

private struct UsageCostLogReadResult {
    var snapshotSize: UInt64
    var bytesRead = 0
    var candidateLines = 0
    var oversizedLines = 0
    var maxBufferedBytes = 0
    var lastCompleteOffset: UInt64
    var trailingLineStartOffset: UInt64?
}

private enum UsageCostLogReaderError: Error {
    case offsetBeyondSnapshot(offset: UInt64, snapshotSize: UInt64)
    case unexpectedEndOfFile(expected: UInt64, actual: UInt64)
}

private struct UsageCostLogReader {
    var chunkSize: Int
    var maximumLineBytes: Int

    func read(
        file: URL,
        fromOffset: UInt64,
        onCandidate: (UsageCostCandidateLine) throws -> Void) throws -> UsageCostLogReadResult
    {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let snapshotSize = try handle.seekToEnd()
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
            bytesRead: bytesRead,
            candidateLines: accumulator.candidateLines,
            oversizedLines: accumulator.oversizedLines,
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
