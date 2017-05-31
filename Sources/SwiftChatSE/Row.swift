//
//  Row.swift
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

open class Row {
	///The columns of this row.
	open let columns: [DatabaseNativeType?]
	
	///A Dictionary mapping the names of this row's columns to their indices in `columns`.
	open let columnNames: [String:Int]
	
	///Initializes a Row with the results of a prepared statement.
	public init(statement: OpaquePointer) {
		var columns = [DatabaseNativeType?]()
		var columnNames = [String:Int]()
		
		for i in 0..<sqlite3_column_count(statement) {
			let value: DatabaseNativeType?
			let type = sqlite3_column_type(statement, i)
			switch type {
			case SQLITE_INTEGER:
				value = sqlite3_column_int64(statement, i)
			case SQLITE_FLOAT:
				value = sqlite3_column_double(statement, i)
			case SQLITE_TEXT:
				value = String(cString: sqlite3_column_text(statement, i))
			case SQLITE_BLOB:
				let bytes = sqlite3_column_bytes(statement, i)
				if bytes == 0 {
					value = Data()
				} else {
					value = Data(bytes: sqlite3_column_blob(statement, i), count: Int(bytes))
				}
			case SQLITE_NULL:
				value = nil
			default:
				fatalError("unrecognized SQLite type \(type)")
			}
			
			columns.append(value)
			columnNames[String(cString: sqlite3_column_name(statement, i))] = Int(i)
		}
		
		self.columns = columns
		self.columnNames = columnNames
	}
	
	
	//MARK: - Convenience functions for accessing columns
	
	
	///Returns the contents of the column at the specified index.
	///
	///- parameter index: The index of the column to return.
	///- parameter type: The type of the column to return.  Will be inferred by the compiler
	///                  if not specified.  Must conform to `DatabaseType`.
	///
	///- returns: The contents of the column, or `nil` if the contents are `NULL`.
	///
	///- warning: Will crash if the index is out of range or the column has an incompatible type.
	open func column<T: DatabaseType>(at index: Int, type: T.Type = T.self) -> T? {
		guard let value = columns[index] else { return nil }
		guard let converted = T.from(native: value) else {
			fatalError("column \(index) has an incompatible type ('\(type(of: value))' could not be converted to '\(type)')")
		}
		return converted
	}
	
	///Returns the contents of the column with the specified name.
	///
	///- parameter name: The name of the column to return.
	///- parameter type: The type of the column to return.  Will be inferred by the compiler
	///                  if not specified.  Must conform to `DatabaseType`.
	///
	///- returns: The contents of the column.
	///
	///- warning: Will crash if the name does not exist or the column has an incompatible type.
	open func column<T: DatabaseType>(named name: String, type: T.Type = T.self) -> T? {
		guard let index = columnNames[name] else {
			fatalError("column '\(name)' not found in \(Array(columnNames.keys))")
		}
		return column(at: index)
	}
}
