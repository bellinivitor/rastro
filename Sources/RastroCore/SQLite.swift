import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// Wrapper mínimo sobre a API C do SQLite que vem no macOS.
final class SQLiteConnection {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "não foi possível abrir \(path)"
            sqlite3_close(handle)
            throw SQLiteError(message: message)
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    var changes: Int { Int(sqlite3_changes(handle)) }
    var lastInsertID: Int64 { sqlite3_last_insert_rowid(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    /// Executa um comando com parâmetros posicionais (`?`).
    func run(_ sql: String, _ params: [Any?] = []) throws {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw error() }
    }

    func query<T>(_ sql: String, _ params: [Any?] = [], row: (Row) -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw error() }
            rows.append(row(Row(statement: statement)))
        }
        return rows
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ params: [Any?]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            switch param {
            case nil:
                sqlite3_bind_null(statement, index)
            case let value as Bool:
                sqlite3_bind_int64(statement, index, value ? 1 : 0)
            case let value as Int64:
                sqlite3_bind_int64(statement, index, value)
            case let value as Int:
                sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Double:
                sqlite3_bind_double(statement, index, value)
            case let value as Date:
                sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
            case let value as String:
                sqlite3_bind_text(statement, index, value, -1, Self.transient)
            default:
                sqlite3_finalize(statement)
                throw SQLiteError(message: "tipo de parâmetro não suportado: \(type(of: param!))")
            }
        }
        return statement
    }

    private func error() -> SQLiteError {
        SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
    }

    struct Row {
        let statement: OpaquePointer?

        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
        func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
        func string(_ column: Int32) -> String { String(cString: sqlite3_column_text(statement, column)) }
        func optionalString(_ column: Int32) -> String? { isNull(column) ? nil : string(column) }
        func date(_ column: Int32) -> Date { Date(timeIntervalSince1970: sqlite3_column_double(statement, column)) }
        func optionalDate(_ column: Int32) -> Date? { isNull(column) ? nil : date(column) }
        func optionalInt64(_ column: Int32) -> Int64? { isNull(column) ? nil : int64(column) }
        func bool(_ column: Int32) -> Bool { int64(column) != 0 }
    }
}
