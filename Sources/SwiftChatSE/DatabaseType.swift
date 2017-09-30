//
//  DatabaseType.swift
//  SwiftChatSE
//
//  Created by NobodyNada on 5/8/17.
//
//

import Foundation
import CSQLite

///A type which can be represented in a SQLite database.
public protocol DatabaseType {
	///Converts `self` to a native type.
	var asNative: DatabaseNativeType { get }
	
	///Converts a `DatabaseNativeType` to this type.
	///- parameter native: The value to convert.
	///- returns: The converted value, or `nil` if a conversion is not possible.
	static func from(native: DatabaseNativeType) -> Self?
	
	///Binds `self` to a prepared statement.
	///- parameter statement: The statement to bind to.
	///- parameter index: The parameter index to bind to.
	///- returns: The status code returned by `sqlite3_bind_*`.
	func bind(to statement: OpaquePointer, index: Int32) -> Int32
}


///A type which can be directly represented in a SQLite databse.
public protocol DatabaseNativeType: DatabaseType {}
public extension DatabaseNativeType {
	var asNative: DatabaseNativeType { return self }
	
	static func from(native: DatabaseNativeType) -> Self? {
		guard let n = native as? Self else { return nil }
		return n
	}
}


///A type which can be converted to a `DatabseNativeType`.
public protocol DatabaseConvertibleType: DatabaseType {}
public extension DatabaseConvertibleType {
	func bind(to statement: OpaquePointer, index: Int32) -> Int32 {
		return asNative.bind(to: statement, index: index)
	}
}



extension Data: DatabaseNativeType {
	public func bind(to statement: OpaquePointer, index: Int32) -> Int32 {
		return withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Int32 in
			let count = self.count
			let bytesCopy = malloc(count)
			memcpy(bytesCopy!, bytes, count)
			
			return sqlite3_bind_blob(statement, index, bytesCopy, Int32(count)) { data in free(data) }
		}
	}
}


extension Double: DatabaseNativeType {
	public func bind(to statement: OpaquePointer, index: Int32) -> Int32 {
		return sqlite3_bind_double(statement, index, self)
	}
}

extension Float: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Double(self) }
	
	public static func from(native: DatabaseNativeType) -> Float? {
		guard let n = native as? Double else { return nil }
		return Float(n)
	}
}


extension Int64: DatabaseNativeType {
	public func bind(to statement: OpaquePointer, index: Int32) -> Int32 {
		return sqlite3_bind_int64(statement, index, self)
	}
}


extension Bool: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return self ? 1 : 0 }
	
	public static func from(native: DatabaseNativeType) -> Bool? {
		guard let n = native as? Int64 else { return nil }
		return n == 0 ? false : true
	}
}

extension Int8: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> Int8? {
		guard let n = native as? Int64 else { return nil }
		return Int8(n)
	}
}
extension Int16: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> Int16? {
		guard let n = native as? Int64 else { return nil }
		return Int16(n)
	}
}
extension Int32: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> Int32? {
		guard let n = native as? Int64 else { return nil }
		return Int32(n)
	}
}
extension Int: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> Int? {
		guard let n = native as? Int64 else { return nil }
		return Int(n)
	}
}

extension UInt8: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> UInt8? {
		guard let n = native as? Int64 else { return nil }
		return UInt8(n)
	}
}
extension UInt16: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> UInt16? {
		guard let n = native as? Int64 else { return nil }
		return UInt16(n)
	}
}
extension UInt32: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> UInt32? {
		guard let n = native as? Int64 else { return nil }
		return UInt32(n)
	}
}
extension UInt: DatabaseConvertibleType {
	public var asNative: DatabaseNativeType { return Int64(self) }
	
	public static func from(native: DatabaseNativeType) -> UInt? {
		guard let n = native as? Int64 else { return nil }
		return UInt(n)
	}
}


extension String: DatabaseNativeType {
	public func bind(to statement: OpaquePointer, index: Int32) -> Int32 {
		let chars = Array(utf8)
		let buf = malloc(chars.count).bindMemory(to: Int8.self, capacity: chars.count)
		memcpy(buf, chars, chars.count)
		
		return sqlite3_bind_text(statement, index, buf, Int32(chars.count)) { data in free(data) }
	}
}
