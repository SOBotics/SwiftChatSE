//
//  DatabaseTests.swift
//  SwiftChatSE
//
//  Created by NobodyNada on 5/8/17.
//
//

import XCTest
@testable import SwiftChatSE

class DatabaseTests: XCTestCase {
	var db: DatabaseConnection!
	
	let testText = "The quick brown fox jumps over the lazy dog."
	
	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
		do {
			try db = DatabaseConnection()
			
			FileManager.default.changeCurrentDirectoryPath("/Users/jonathan/Desktop")
		} catch {
			XCTFail("DatabaseConnection.init() threw an error: \(error)")
			return
		}
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		db = nil
		super.tearDown()
	}
	
	func testOnDiskDatabase() {
		do {
			let _ = try DatabaseConnection("test.sqlite3")
		} catch {
			XCTFail("DatabaseConnection.init(_:) threw an error: \(error)")
		}
		
		//clean up
		let _ = try? FileManager.default.removeItem(atPath: "test.sqlite3")
	}
	
	func testBasicQuery() throws {
		XCTAssert(try db.run(
			"CREATE TABLE test (" +
				"id INTEGER PRIMARY KEY NOT NULL," +
				"someText TEXT" +
			");"
			).isEmpty, "CREATE TABLE should not return any rows"
		)
		
		XCTAssert(try db.run(
			"INSERT INTO test (someText) VALUES (?);", testText
			).isEmpty, "INSERT should not return any rows"
		)
		
		let results = try db.run("SELECT * FROM test")
		XCTAssert(results.count == 1, "results should have exactly one element")
		
		if let result = results.first {
			XCTAssert(result.columnNames.count == 2)
			XCTAssert(result.columns.count == 2)
			
			XCTAssert(result.columnNames["id"] == 0)
			XCTAssert(result.columnNames["someText"] == 1)
			
			XCTAssert(result.columns.last as? String == testText)
			
			XCTAssert((result.column(named: "someText") as String?) == testText)
		}
	}
	
	func testNull() throws {
		XCTAssert(try db.run(
			"CREATE TABLE test (" +
				"id INTEGER PRIMARY KEY NOT NULL," +
				"someText TEXT" +
			");"
			).isEmpty, "CREATE TABLE should not return any rows"
		)
		
		XCTAssert(try db.run(
			"INSERT INTO test (someText) VALUES (?);", nil
			).isEmpty, "INSERT should not return any rows"
		)
		
		let results = try db.run("SELECT * FROM test")
		XCTAssert(results.count == 1, "results should have exactly one element")
		
		if let result = results.first {
			XCTAssert((result.column(named: "someText") as String?) == nil)
		}
	}
	
	func testTransactions() throws {
		try db.run(
			"CREATE TABLE test (" +
				"id INTEGER PRIMARY KEY NOT NULL," +
				"someText TEXT" +
			");")
		
		try db.performTransaction {
			try db.run("INSERT INTO test (someText) VALUES (?);", testText)
			try db.run("INSERT INTO test (someText) VALUES (?);", testText)
		}
		
		XCTAssert(try db.run("SELECT COUNT(*) FROM test").first?.column(at: 0) == 2, "Transactions should work")
		
		
		
		XCTAssertThrowsError(try db.performTransaction {
			try db.run("INSERT INTO test (someText) VALUES (?);", testText)
			try db.run("HAJSDFLKJAHSDFALSDF;")
			try db.run("DELETE FROM test;")
		}, "A failed transaction should throw an error")
		
		XCTAssert(try db.run("SELECT COUNT(*) FROM test").first?.column(at: 0)  == 2,
		          "An invalid transaction should not have any effects"
		)
		
		
		
		try db.performTransaction {
			try db.run("DELETE FROM test;")
			return
		}
		
		XCTAssert(try db.run("SELECT COUNT(*) FROM test").first?.column(at: 0)  == 0, "Transactions should work")
	}
	
	func testMigrations() throws {
		try db.run(
			"CREATE TABLE test (" +
				"id INTEGER PRIMARY KEY NOT NULL," +
				"someText TEXT" +
		");")
		
		try db.migrate {
			try db.run("INSERT INTO test (someText) VALUES (?);", testText)
		}
		
		let results = try db.run("SELECT * FROM test")
		XCTAssert(results.count == 1, "results should have exactly one element")
		
		if let result = results.first {
			XCTAssert((result.column(named: "someText") as String?) == testText)
		}
		
		try db.migrate("testing") {}
		try db.migrate("testing") { XCTFail("migration was performed twice") }
	}
	
	
	func testReadOnlyDatabase() throws {
		let db = try DatabaseConnection(":memory:", options: [.readOnly])
		
		do {
			try db.run("CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT);")
			XCTFail("CREATE TABLE did not throw an error")
		} catch DatabaseError.sqliteError(let error, _){
			XCTAssert(error == .readOnly, "CREATE TABLE should throw a readOnly error")
		}
	}
	
	
	static var allTests : [(String, (DatabaseTests) -> () throws -> Void)] {
		return [
			("testOnDiskDatabse", testOnDiskDatabase),
			("testBasicQuery", testBasicQuery),
			("testNull", testNull),
			("testTransactions", testTransactions),
			("testMigrations", testMigrations),
			("testReadOnlyDatabase", testReadOnlyDatabase)
		]
	}
}
