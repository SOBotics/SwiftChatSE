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
    import CSQLiteLinux
#else
    import CSQLite
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
    open let db: OpaquePointer
    
    ///A cache of prepared statements.
    open var statementCache = [String:OpaquePointer]()
    
    
    private var queue = DispatchQueue(label: "org.sobotics.swiftchatse.DatabaseConnection")
    //A thread which is currently performing a transaction.  Used to detect when
    //`run` is erronously called from inside a transaction
    private var transactionThread: pthread_t?
    
    
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
        _ migration: ((DatabaseTransaction) throws -> Void)
        ) throws {
        
        try transact {t in
            //Create the migration table if it does not exist already.
            try t.run("CREATE TABLE IF NOT EXISTS migrations (name TEXT NOT NULL);")
            try t.run("CREATE UNIQUE INDEX IF NOT EXISTS migration_index ON migrations (name);")
            
            //Check if this migration already exists.
            let exists: Int? = try t.run(
                "SELECT EXISTS(SELECT * FROM migrations WHERE name = ? LIMIT 1);",
                name
                ).first?.column(at: 0) ?? 0
            
            if (exists ?? 0) == 0 {
                //Run the migration.
                try migration(t)
                
                try t.run("INSERT INTO migrations (name) VALUES (?)", name)
            }
        }
    }
    
    ///Performs a database transaction.
    ///
    ///A [database transaction](https://en.wikipedia.org/wiki/Database_transaction) is an atomic unit of work,
    ///guaranteed to either complete entirely or not at all.
    ///
    ///If either the transaction block or the `COMMIT` statement throws an error,
    ///the transaction will be automatically rolled back.  If this function throws an error,
    ///you may assume none of the database statements run by `transaction` have been performed.
    
    ///- parameter transaction: The code to run inside of the transaction.
    open func transact<Result>(_ block: ((DatabaseTransaction) throws -> Result)) throws -> Result {
        guard transactionThread == nil || transactionThread != pthread_self() else {
            fatalError("Recursive transactions are not allowed.")
        }
        
        return try queue.sync {
            transactionThread = pthread_self()
            defer { transactionThread = nil }
            
            var result: Result!
            var error: Error?
            let transaction = DatabaseTransaction(db: self)
            
            
            do {
                try transaction.begin()
            } catch {
                transaction.state = .rolledBack
                throw error
            }
            
            
            do {
                result = try block(transaction)
                if transaction.state == .inProgress { transaction.state = .committed }
            } catch let e {
                error = e
                transaction.rollback()
            }
            
            
            try transaction.complete()
            
            if let e = error {
                throw e
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
        
        guard transactionThread == nil || transactionThread != pthread_self() else {
            fatalError(
                "Do not call run on a DatabaseConnection from inside a transaction; " +
                "use the DatabaseTransaction's run method instead."
            )
        }
        
        return try queue.sync {
            try _run(query, namedParameters: namedParameters, indexedParameters: indexedParameters)
        }
        
    }
    
    @discardableResult fileprivate func _run(
        _ query: String,
        namedParameters: [String:DatabaseType?],
        indexedParameters: [DatabaseType?],
        cache: Bool = true
        ) throws -> [Row] {
        
        
        
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
            let result = sqlite3_prepare_v2(
                db,
                query,
                -1,
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


///A `DatabaseTransaction` represents a transaction in the database.
///Do not create a `DatabaseTransaction` yourself; use `DatabaseConnection`'s `transact` method instead.
///
///A [database transaction](https://en.wikipedia.org/wiki/Database_transaction) is an atomic unit of work,
///guaranteed to either complete entirely or not at all.
public class DatabaseTransaction {
    ///The `DatabaseConnection` on which this transaction is operating.
    public let db: DatabaseConnection
    
    public enum State {
        ///The transaction has not yet been completed.
        case inProgress
        
        ///The transaction was rolled back.
        case rolledBack
        
        ///The transaction was completed.
        case committed
    }
    
    ///The `State` of this transaction.
    public fileprivate(set) var state: State = .inProgress
    
    fileprivate init(db: DatabaseConnection) {
        self.db = db
    }
    
    ///Marks a database transaction for rollback.
    ///Queries may not be run on a transaction which has been marked for rollback.
    ///The rollback will be performed once the `transact` block completes.
    public func rollback() {
        if state == .committed {
            fatalError("attemt to  rollback a committed transaction")
        }
        
        state = .rolledBack
    }
    
    fileprivate func commit() {
        if state == .rolledBack {
            fatalError("attempt to commit a rolled-back transaction")
        }
        
        state = .committed
    }
    
    fileprivate func begin() throws {
        try run("BEGIN;")
    }
    
    fileprivate func complete() throws {
        do {
            switch state {
            case .inProgress:
                fatalError("attempt to complete an in-progress transaction")
            case .rolledBack:
                try db._run("ROLLBACK;", namedParameters: [:], indexedParameters: [])
            case .committed:
                try db._run("COMMIT;", namedParameters: [:], indexedParameters: [])
            }
        } catch {
            let _ = try? db._run("ROLLBACK;", namedParameters: [:], indexedParameters: [])
            state = .rolledBack
            throw error
        }
    }
    
    ///Runs a single SQL statement, binding the specified parameters.
    ///- parameter query: The SQL statement to run.
    ///- parameter parameters: A dictionary containing names and values to bind to the SQL statement's named parameters, like `:id`.
    ///- parameter cache: Whether the compiled statement should be cached.  Default is `true`.
    @discardableResult public func run(
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
    @discardableResult public func run(
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
    @discardableResult public func run(
        _ query: String,
        namedParameters: [String:DatabaseType?],
        indexedParameters: [DatabaseType?],
        cache: Bool = true
        ) throws -> [Row] {
        
        if state != .inProgress {
            fatalError("attempt to run a query on a \(state == .rolledBack ? "rolled-back" : "committed") transaction")
        }
        
        return try db._run(query, namedParameters: namedParameters, indexedParameters: indexedParameters)
    }
}
