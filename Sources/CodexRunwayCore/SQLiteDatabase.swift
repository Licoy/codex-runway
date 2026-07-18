import Foundation
import SQLite3

struct SQLiteError: Error, Equatable, CustomStringConvertible {
    let operation: String
    let code: Int32
    let message: String

    var description: String {
        "SQLite \(operation) failed (code \(code)): \(message)"
    }
}

struct SQLiteRollbackError: Error, CustomStringConvertible {
    let primary: any Error
    let rollback: SQLiteError

    var description: String {
        let primaryMessage = (primary as? SQLiteError).map { "Primary error: \($0). " } ?? ""
        return "\(primaryMessage)Rollback error: \(rollback)"
    }
}

final class SQLiteDatabase {
    fileprivate let handle: OpaquePointer

    init(url: URL) throws {
        var openedHandle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &openedHandle, flags, nil)

        guard code == SQLITE_OK, let openedHandle else {
            let message = openedHandle.map(sqliteMessage) ?? String(cString: sqlite3_errstr(code))
            if let openedHandle {
                sqlite3_close_v2(openedHandle)
            }
            throw SQLiteError(operation: "open", code: code, message: message)
        }

        handle = openedHandle
        try configure()
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String, operation: String = "execute") throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw makeError(operation: operation, code: code)
        }
    }

    func prepare(_ sql: String, operation: String = "prepare") throws -> SQLiteStatement {
        var statementHandle: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statementHandle, nil)

        guard code == SQLITE_OK, let statementHandle else {
            if let statementHandle {
                sqlite3_finalize(statementHandle)
            }
            throw makeError(operation: operation, code: code)
        }

        return SQLiteStatement(database: self, handle: statementHandle)
    }

    func withStatement<Result>(
        _ sql: String,
        operation: String = "prepare",
        _ body: (SQLiteStatement) throws -> Result
    ) throws -> Result {
        let statement = try prepare(sql, operation: operation)
        return try body(statement)
    }

    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE", operation: "begin transaction")
        do {
            let result = try body()
            try execute("COMMIT", operation: "commit transaction")
            return result
        } catch {
            do {
                try execute("ROLLBACK", operation: "rollback transaction")
            } catch let rollback as SQLiteError {
                throw SQLiteRollbackError(primary: error, rollback: rollback)
            }
            throw error
        }
    }

    var changes: Int32 {
        sqlite3_changes(handle)
    }

    fileprivate func makeError(operation: String, code: Int32? = nil) -> SQLiteError {
        SQLiteError(
            operation: operation,
            code: code ?? sqlite3_errcode(handle),
            message: sqliteMessage(handle))
    }

    private func configure() throws {
        let busyCode = sqlite3_busy_timeout(handle, 5_000)
        guard busyCode == SQLITE_OK else {
            throw makeError(operation: "configure busy timeout", code: busyCode)
        }
        try execute("PRAGMA foreign_keys = ON", operation: "enable foreign keys")
        try execute("PRAGMA journal_mode = WAL", operation: "enable WAL")
        try execute("PRAGMA synchronous = NORMAL", operation: "configure synchronous mode")
    }
}

final class SQLiteStatement {
    private let database: SQLiteDatabase
    private let handle: OpaquePointer

    fileprivate init(database: SQLiteDatabase, handle: OpaquePointer) {
        self.database = database
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(handle, index, value), operation: "bind integer")
    }

    func bind(_ value: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(handle, index, value), operation: "bind double")
    }

    func bind(_ value: String, at index: Int32) throws {
        let bytes = value.utf8CString
        guard bytes.count - 1 <= Int(Int32.max) else {
            throw SQLiteError(
                operation: "bind text",
                code: SQLITE_TOOBIG,
                message: String(cString: sqlite3_errstr(SQLITE_TOOBIG)))
        }
        let code = bytes.withUnsafeBufferPointer { buffer in
            sqlite3_bind_text(
                handle,
                index,
                buffer.baseAddress,
                Int32(buffer.count - 1),
                sqliteTransient)
        }
        try check(code, operation: "bind text")
    }

    func bind(_ value: Data, at index: Int32) throws {
        guard value.count <= Int(Int32.max) else {
            throw SQLiteError(
                operation: "bind blob",
                code: SQLITE_TOOBIG,
                message: String(cString: sqlite3_errstr(SQLITE_TOOBIG)))
        }
        guard !value.isEmpty else {
            try check(sqlite3_bind_zeroblob(handle, index, 0), operation: "bind blob")
            return
        }
        let code = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(handle, index, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
        }
        try check(code, operation: "bind blob")
    }

    func bindNull(at index: Int32) throws {
        try check(sqlite3_bind_null(handle, index), operation: "bind null")
    }

    func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw database.makeError(operation: "step statement", code: code)
        }
    }

    func reset() throws {
        let resetCode = sqlite3_reset(handle)
        let clearCode = sqlite3_clear_bindings(handle)
        try check(resetCode, operation: "reset statement")
        try check(clearCode, operation: "clear bindings")
    }

    func columnIsNull(_ index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    func columnType(_ index: Int32) -> Int32 {
        sqlite3_column_type(handle, index)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    func columnString(_ index: Int32) -> String? {
        guard !columnIsNull(index) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, index))
        guard count > 0 else { return "" }
        guard let pointer = sqlite3_column_text(handle, index) else { return nil }
        return String(data: Data(bytes: pointer, count: count), encoding: .utf8)
    }

    func columnData(_ index: Int32) -> Data? {
        guard !columnIsNull(index) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, index))
        guard count > 0 else { return Data() }
        guard let pointer = sqlite3_column_blob(handle, index) else { return nil }
        return Data(bytes: pointer, count: count)
    }

    private func check(_ code: Int32, operation: String) throws {
        guard code == SQLITE_OK else {
            throw database.makeError(operation: operation, code: code)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func sqliteMessage(_ handle: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(handle))
}
