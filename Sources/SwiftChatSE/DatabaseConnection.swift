//
//  Database.swift
//  SwiftChatSE
//
//  Created by NobodyNada on 5/8/17.
//
//

import Foundation

#if os(Linux)
	import CSQLiteLinux
#else
	import CSQLite
#endif


enum DatabaseError: Error {
	case unknownSQLiteError(code: Int32, message: String?)
	case sqliteError(error: SQLiteError, message: String?)
	case noSuchParameter(name: String)
}

enum SQLiteError: Int32 {
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

class DatabaseConnection {
	let db: OpaquePointer
	
	//A cache of prepared statements.
	var statementCache = [String:OpaquePointer]()
	
	init(_ filename: String) throws {
		var connection: OpaquePointer?
		
		let result = sqlite3_open(filename, &connection)
		guard result == SQLITE_OK, connection != nil else {
			try throwSQLiteError(code: result, db: nil)
		}
		
		db = connection!
	}
	
	convenience init() throws {
		try self.init(":memory:")
	}
	
	deinit {
		for (_, statement) in statementCache {
			sqlite3_finalize(statement)
		}
		sqlite3_close_v2(db)
	}
	
	
	func migrate(
		_ name: String? = nil,
		file: String = #file,
		function: String = #function,
		line: Int = #line,
		_ migration: (() throws -> Void)
		) throws {
		
		let name = name ?? "\(file):\(function):\(line)"
		
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
	func performTransaction<Result>(_ transaction: (() throws -> Result)) throws -> Result {
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
	
	///Runs a single SQL statement, binding the specified parameters.
	///- parameter query: The SQL statement to run.
	///- parameter indexedParameters: The values to bind to the SQL statement's unnamed or indexed parameters, like `?`.
	///- parameter namedParameters: The values to bind to the SQL statement's named parameters, like `:id`.
	///- parameter cache: Whether the compiled statement should be cached.  Default is `true`.
	@discardableResult func run(
		_ query: String,
		_ indexedParameters: DatabaseType?...,
		_ namedParameters: [String:DatabaseType?] = [:],
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
				try throwSQLiteError(code: result, db: nil)
			}
			if tail != nil && tail!.pointee != 0 {
				//programmer error, so crash instead of throwing
				fatalError("\(#function) does not accept multiple statements: '\(query)'")
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
				result = param.asNative.bind(to: statement, index: Int32(i + 1))
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
				result = v.asNative.bind(to: statement, index: index)
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
