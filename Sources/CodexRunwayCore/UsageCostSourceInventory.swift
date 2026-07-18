import CryptoKit
import Darwin
import Foundation

enum UsageCostSourceRoot: String, CaseIterable, Sendable {
    case sessions
    case archivedSessions = "archived_sessions"
}

struct UsageCostSourceFile: Equatable, Sendable {
    let url: URL
    let root: UsageCostSourceRoot
    let basename: String
    let device: Int64
    let inode: Int64
    let birthNanoseconds: Int64
    let modificationNanoseconds: Int64
    let statusChangeNanoseconds: Int64
    let size: UInt64
}

struct UsageCostFileHash: Equatable, Sendable {
    let digest: Data
    let bytesRead: Int
}

enum UsageCostSourceInventoryError: Error, Equatable {
    case cannotEnumerate(UsageCostSourceRoot)
    case filesystem(operation: String, code: Int32)
    case invalidFileSize
    case timestampOverflow
    case hashRangeBeyondSnapshot(upperBound: UInt64, snapshotSize: UInt64)
    case unexpectedEndOfFile(expected: UInt64, actual: UInt64)
    case sourceIdentityChanged
}

enum UsageCostSourceInventory {
    static func files(in codexHome: URL) throws -> [UsageCostSourceFile] {
        var result = [UsageCostSourceFile]()
        for root in UsageCostSourceRoot.allCases {
            try Task.checkCancellation()
            result += try files(in: codexHome.appendingPathComponent(root.rawValue), root: root)
        }
        return result.sorted {
            ($0.root.rawValue, $0.url.path) < ($1.root.rawValue, $1.url.path)
        }
    }

    private static func files(
        in rootURL: URL,
        root: UsageCostSourceRoot
    ) throws -> [UsageCostSourceFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else { throw UsageCostSourceInventoryError.cannotEnumerate(root) }

        var enumerationError: (any Error)?
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) { _, error in
            enumerationError = error
            return false
        }
        guard let enumerator else { throw UsageCostSourceInventoryError.cannotEnumerate(root) }

        var result = [UsageCostSourceFile]()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            try Task.checkCancellation()
            if let source = try sourceFile(at: url, root: root) {
                result.append(source)
            }
        }
        if enumerationError != nil { throw UsageCostSourceInventoryError.cannotEnumerate(root) }
        return result
    }

    private static func sourceFile(
        at url: URL,
        root: UsageCostSourceRoot
    ) throws -> UsageCostSourceFile? {
        var metadata = stat()
        let code = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &metadata)
        }
        guard code == 0 else {
            throw UsageCostSourceInventoryError.filesystem(operation: "stat", code: errno)
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else { return nil }
        guard metadata.st_size >= 0 else {
            throw UsageCostSourceInventoryError.invalidFileSize
        }
        return UsageCostSourceFile(
            url: url,
            root: root,
            basename: url.lastPathComponent,
            device: Int64(metadata.st_dev),
            inode: Int64(bitPattern: UInt64(metadata.st_ino)),
            birthNanoseconds: try timestampNanoseconds(metadata.st_birthtimespec),
            modificationNanoseconds: try timestampNanoseconds(metadata.st_mtimespec),
            statusChangeNanoseconds: try timestampNanoseconds(metadata.st_ctimespec),
            size: UInt64(metadata.st_size))
    }
}

enum UsageCostFileHasher {
    static let chunkSize = 256 * 1_024

    static func sha256(
        of file: UsageCostSourceFile,
        range: Range<UInt64>,
        chunkSize: Int = chunkSize
    ) throws -> UsageCostFileHash {
        try hash(
            url: file.url,
            expected: file,
            requestedRange: range,
            requireStableMetadata: false,
            chunkSize: chunkSize)
    }

    static func fullSHA256(
        of file: UsageCostSourceFile,
        chunkSize: Int = chunkSize
    ) throws -> UsageCostFileHash {
        try hash(
            url: file.url,
            expected: file,
            requestedRange: nil,
            requireStableMetadata: true,
            chunkSize: chunkSize)
    }

    private static func hash(
        url: URL,
        expected: UsageCostSourceFile?,
        requestedRange: Range<UInt64>?,
        requireStableMetadata: Bool,
        chunkSize: Int
    ) throws -> UsageCostFileHash {
        precondition(chunkSize > 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let metadata = try snapshotMetadata(of: handle)
        if let expected {
            guard Int64(metadata.st_dev) == expected.device,
                  Int64(bitPattern: UInt64(metadata.st_ino)) == expected.inode,
                  try timestampNanoseconds(metadata.st_birthtimespec) == expected.birthNanoseconds
            else { throw UsageCostSourceInventoryError.sourceIdentityChanged }
            if requireStableMetadata {
                guard UInt64(metadata.st_size) == expected.size,
                      try timestampNanoseconds(metadata.st_mtimespec)
                        == expected.modificationNanoseconds,
                      try timestampNanoseconds(metadata.st_ctimespec)
                        == expected.statusChangeNanoseconds
                else { throw UsageCostSourceInventoryError.sourceIdentityChanged }
            }
        }
        let snapshotSize = UInt64(metadata.st_size)
        let range = requestedRange ?? 0..<snapshotSize
        guard range.upperBound <= snapshotSize else {
            throw UsageCostSourceInventoryError.hashRangeBeyondSnapshot(
                upperBound: range.upperBound,
                snapshotSize: snapshotSize)
        }
        try handle.seek(toOffset: range.lowerBound)

        var hasher = SHA256()
        var position = range.lowerBound
        while position < range.upperBound {
            try Task.checkCancellation()
            let requested = min(chunkSize, Int(range.upperBound - position))
            let chunk = try autoreleasepool {
                try handle.read(upToCount: requested) ?? Data()
            }
            guard !chunk.isEmpty else {
                throw UsageCostSourceInventoryError.unexpectedEndOfFile(
                    expected: range.upperBound,
                    actual: position)
            }
            hasher.update(data: chunk)
            position += UInt64(chunk.count)
        }
        if requireStableMetadata {
            let finalMetadata = try snapshotMetadata(of: handle)
            guard finalMetadata.st_dev == metadata.st_dev,
                  finalMetadata.st_ino == metadata.st_ino,
                  finalMetadata.st_size == metadata.st_size,
                  finalMetadata.st_birthtimespec.tv_sec == metadata.st_birthtimespec.tv_sec,
                  finalMetadata.st_birthtimespec.tv_nsec == metadata.st_birthtimespec.tv_nsec,
                  finalMetadata.st_mtimespec.tv_sec == metadata.st_mtimespec.tv_sec,
                  finalMetadata.st_mtimespec.tv_nsec == metadata.st_mtimespec.tv_nsec,
                  finalMetadata.st_ctimespec.tv_sec == metadata.st_ctimespec.tv_sec,
                  finalMetadata.st_ctimespec.tv_nsec == metadata.st_ctimespec.tv_nsec
            else { throw UsageCostSourceInventoryError.sourceIdentityChanged }
        }
        return UsageCostFileHash(
            digest: Data(hasher.finalize()),
            bytesRead: Int(range.upperBound - range.lowerBound))
    }

    private static func snapshotMetadata(of handle: FileHandle) throws -> stat {
        var metadata = stat()
        guard Darwin.fstat(handle.fileDescriptor, &metadata) == 0 else {
            throw UsageCostSourceInventoryError.filesystem(operation: "fstat", code: errno)
        }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size >= 0 else {
            throw UsageCostSourceInventoryError.invalidFileSize
        }
        return metadata
    }
}

private func timestampNanoseconds(_ time: timespec) throws -> Int64 {
    let (seconds, multipliedOverflow) = Int64(time.tv_sec).multipliedReportingOverflow(by: 1_000_000_000)
    let (result, addedOverflow) = seconds.addingReportingOverflow(Int64(time.tv_nsec))
    guard !multipliedOverflow, !addedOverflow else {
        throw UsageCostSourceInventoryError.timestampOverflow
    }
    return result
}
