//
//  Database.swift
//  SwiftChatSE
//
//  Created by NobodyNada on 5/8/17.
//
//

import Foundation
import Dispatch

#if os(Linux)
    import CSQLite
#else
    import SQLite3
#endif

public enum DatabaseError: Error {
    case unknownSQLiteError(code: Int32, message: String?)
    case sqliteError(error: SQLiteError, message: String?)
    case noSuchParameter(name: String)
}

public enum SQLiteError: Int32 {
    case genericError = 1
    case aborted = 4
    case notAuthenticated = 23
    case busy = 5
    case cantOpen = 14
    case constraint = 19
    case corrupt = 11
    case diskFull = 13
    case internalError = 2
    case interrupt = 9
    case ioError = 10
    case locked = 6
    case datatypeMismatch = 20
    case misuse = 21
    case noLargeFileSupport = 22
    case outOfMemory = 7
    case notADatabase = 12
    case noPermissions = 3
    case protocolError = 15
    case indexOutOfRange = 25
    case readOnly = 8
    case schemaChagned = 17
    case stringOrBlobTooBig = 18
}

private func throwSQLiteError(code: Int32, db: OpaquePointer?) throws -> Never {
    let messagePtr = sqlite3_errmsg(db)
    let message = messagePtr.map { String(cString: $0) }
    
    if let error = SQLiteError(rawValue: code) {
        throw DatabaseError.sqliteError(error: error, message: message)
    }
    throw DatabaseError.unknownSQLiteError(code: code, message: message)
}

open class DatabaseConnection {
    public let db: OpaquePointer
    
    //A cache of prepared statements.
    open var statementCache = [String:OpaquePointer]()
    
    private let queue = DispatchQueue(label: "org.sobotics.swiftchatse.database")
    private static let specificKey = DispatchSpecificKey<OpaquePointer>()
    
    public struct SQLiteOpenFlags: OptionSet {
        public var rawValue: Int32
        
        public init(rawValue: Int32) { self.rawValue = rawValue }
        
        public static let readOnly = SQLiteOpenFlags(rawValue: SQLITE_OPEN_READONLY)
        public static let readWrite = SQLiteOpenFlags(rawValue: SQLITE_OPEN_READWRITE)
        public static let createIfNotExists = SQLiteOpenFlags(rawValue: SQLITE_OPEN_CREATE)
        public static let allowURIFilenames  = SQLiteOpenFlags(rawValue: SQLITE_OPEN_CREATE)
        public static let memory = SQLiteOpenFlags(rawValue: SQLITE_OPEN_MEMORY)
        public static let noMutex = SQLiteOpenFlags(rawValue: SQLITE_OPEN_NOMUTEX)
        public static let fullMutex = SQLiteOpenFlags(rawValue: SQLITE_OPEN_FULLMUTEX)
        public static let sharedCache = SQLiteOpenFlags(rawValue: SQLITE_OPEN_SHAREDCACHE)
        public static let privateCache = SQLiteOpenFlags(rawValue: SQLITE_OPEN_PRIVATECACHE)
    }
    public init(_ filename: String, options: SQLiteOpenFlags = []) throws {
        var connection: OpaquePointer?
        var flags = options
        
        if (flags.contains(.readOnly) && (flags.contains(.readWrite)) || flags.contains(.createIfNotExists)) {
            fatalError("SQLiteOpenFlags.readOnly is incompatible with .readWrite and .createIfNotExists")
        }
        if !flags.contains(.readOnly) && !flags.contains(.readWrite) {
            flags.insert(.readWrite)
            flags.insert(.createIfNotExists)
        }
        
        let result = sqlite3_open_v2(filename, &connection, flags.rawValue, nil)
        guard result == SQLITE_OK, connection != nil else {
            try throwSQLiteError(code: result, db: nil)
        }
        
        db = connection!
        queue.setSpecific(key: DatabaseConnection.specificKey, value: db)
        
        busyTimeout = 1
        sqlite3_busy_timeout(db, 1000)
    }
    
    public convenience init() throws {
        try self.init(":memory:")
    }
    
    deinit {
        for (_, statement) in statementCache {
            sqlite3_finalize(statement)
        }
        sqlite3_close_v2(db)
    }
    
    ///The primary key inserted by the last `INSERT` statement,
    ///or 0 if no successful `INSERT` statements have been performed by this connection.
    open var lastInsertedPrimaryKey: Int64 {
        return sqlite3_last_insert_rowid(db)
    }
    
    ///The amount of time to wait before a query will time out with `SQLiteError.busy`.
    ///Default is 1 second.
    open var busyTimeout: TimeInterval {
        didSet {
            sqlite3_busy_timeout(db, Int32(busyTimeout * 1000))
        }
    }
    
    open func migrate(
        _ name: String,
        _ migration: (() throws -> Void)
        ) throws {
        
        try performTransaction {
            //Create the migration table if it does not exist already.
            try run("CREATE TABLE IF NOT EXISTS migrations (name TEXT NOT NULL);")
            try run("CREATE UNIQUE INDEX IF NOT EXISTS migration_index ON migrations (name);")
            
            //Check if this migration already exists.
            let exists: Int? = try run(
                "SELECT EXISTS(SELECT * FROM migrations WHERE name = ? LIMIT 1);",
                name
                ).first?.column(at: 0) ?? 0
            
            if (exists ?? 0) == 0 {
                //Run the migration.
                try migration()
                
                try run("INSERT INTO migrations (name) VALUES (?)", name)
            }
        }
    }
    
    ///Performs a database transaction.
    ///
    ///A [database transaction](https://en.wikipedia.org/wiki/Database_transaction) is an atomic unit of work,
    ///guaranteed to either complete entirely or not at all.
    ///
    ///If either the transaction block or the `COMMIT` statement throw an error,
    ///the transaction will be automatically rolled back.  If this function throws an error,
    ///you may assume none of the database statements run by `transaction` have been performed.
    
    ///- parameter transaction: The code to run inside of the transaction.
    open func performTransaction<Result>(_ transaction: (() throws -> Result)) throws -> Result {
        return try onQueue {
            let result: Result
            try run("BEGIN;")
            do {
                result = try transaction()
                try run("COMMIT;")
            } catch {
                try run("ROLLBACK;")
                throw error
            }
            
            return result
        }
    }
    
    
    
    ///Runs a single SQL statement, binding the specified parameters.
    ///- parameter query: The SQL statement to run.
    ///- parameter parameters: A dictionary containing names and values to bind to the SQL statement's named parameters, like `:id`.
    ///- parameter cache: Whether the compiled statement should be cached.  Default is `true`.
    @discardableResult open func run(
        _ query: String,
        _ parameters: [String:DatabaseType?],
        cache: Bool = true
        ) throws -> [Row] {
        
        return try run(query, namedParameters: parameters, indexedParameters: [])
    }
    
    ///Runs a single SQL statement, binding the specified parameters.
    ///- parameter query: The SQL statement to run.
    ///- parameter parameters: The values to bind to the SQL statement's unnamed or indexed parameters, like `?`.
    ///- parameter cache: Whether the compiled statement should be cached.  Default is `true`.
    @discardableResult open func run(
        _ query: String,
        _ parameters: DatabaseType?...,
        cache: Bool = true
        ) throws -> [Row] {
        
        return try run(query, namedParameters: [:], indexedParameters: parameters)
    }
    
    
    ///Runs a single SQL statement, binding the specified parameters.
    ///- parameter query: The SQL statement to run.
    ///- parameter indexedParameters: The values to bind to the SQL statement's unnamed or indexed parameters, like `?`.
    ///- parameter namedParameters: The values to bind to the SQL statement's named parameters, like `:id`.
    ///- parameter cache: Whether the compiled statement should be cached.  Default is `true`.
    @discardableResult open func run(
        _ query: String,
        namedParameters: [String:DatabaseType?],
        indexedParameters: [DatabaseType?],
        cache: Bool = true
        ) throws -> [Row] {
        
        return try onQueue { try _run(query, namedParameters: namedParameters, indexedParameters: indexedParameters, cache: cache) }
        
    }
    
    private func onQueue<T>(execute work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: DatabaseConnection.specificKey) == db {
            return try work()
        } else {
            return try queue.sync(execute: work)
        }
    }
    
    private func _run(_ query: String,
                      namedParameters: [String:DatabaseType?],
                      indexedParameters: [DatabaseType?],
                      cache: Bool) throws -> [Row] {
        //Compile the query.
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let statement: OpaquePointer
        
        if cache, let cached = statementCache[query] {
            //cache hit; use the cached query instead of recompiling
            statement = cached
        } else {
            //cache miss; compile the query
            var tail: UnsafePointer<Int8>?
            var stmt: OpaquePointer?
            try query.utf8CString.withUnsafeBufferPointer {
                let result = sqlite3_prepare_v2(
                    db,
                    $0.baseAddress,
                    Int32($0.count),
                    &stmt,
                    &tail
                )
                
                
                guard result == SQLITE_OK, stmt != nil else {
                    try throwSQLiteError(code: result, db: db)
                }
                if tail != nil && tail!.pointee != 0 {
                    //programmer error, so crash instead of throwing
                    fatalError("\(#function) does not accept multiple statements: '\(query)' (tail: \(String(cString: tail!)))")
                }
            }
            
            statement = stmt!
            
            //If caching is enabled, store the compiled query
            if cache { statementCache[query] = statement }
        }
        
        defer {
            //Reset the query if it is cached, or dispose of it otherwise.
            if cache {
                sqlite3_clear_bindings(statement)
                sqlite3_reset(statement)
            } else {
                sqlite3_finalize(statement)
            }
        }
        
        
        
        //Bind the parameters.
        for i in 0..<indexedParameters.count {
            let result: Int32
            
            if let param = indexedParameters[i] {
                result = param.bind(to: statement, index: Int32(i + 1))
            } else {
                result = sqlite3_bind_null(statement, Int32(i + 1))
            }
            
            guard result == SQLITE_OK else {
                try throwSQLiteError(code: result, db: db)
            }
        }
        
        
        for (name, value) in namedParameters {
            let index = sqlite3_bind_parameter_index(statement, name)
            if index == 0 {
                throw DatabaseError.noSuchParameter(name: name)
            }
            
            let result: Int32
            if let v = value {
                result = v.bind(to: statement, index: index)
            } else {
                result = sqlite3_bind_null(statement, index)
            }
            
            guard result == SQLITE_OK else {
                try throwSQLiteError(code: result, db: db)
            }
        }
        
        
        
        //Run the query.
        var done = false
        var results: [Row] = []
        repeat {
            let result = sqlite3_step(statement)
            
            switch result {
            case SQLITE_DONE:
                done = true
            case SQLITE_ROW:
                //we got a row
                results.append(Row(statement: statement))
                break
            default:
                try throwSQLiteError(code: result, db: db)
            }
        } while !done
        
        return results
    }
}
