import Darwin
import Foundation

public final class SingleInstanceGuard: @unchecked Sendable, Equatable {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    public static func == (lhs: SingleInstanceGuard, rhs: SingleInstanceGuard) -> Bool {
        lhs.fileDescriptor == rhs.fileDescriptor
    }

    public static func acquire(lockURL: URL = defaultLockURL()) throws -> SingleInstanceGuard? {
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return SingleInstanceGuard(fileDescriptor: fd)
        }
        let code = POSIXErrorCode(rawValue: errno) ?? .EIO
        close(fd)
        if code == .EWOULDBLOCK { return nil }
        throw POSIXError(code)
    }

    public static func defaultLockURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Runway", isDirectory: true)
            .appendingPathComponent("codex-runway.lock")
    }
}
