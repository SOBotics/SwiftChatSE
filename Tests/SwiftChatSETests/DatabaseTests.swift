//
//  DatabaseTests.swift
//  SwiftChatSE
//
//  Created by Jonathan Keller on 5/8/17.
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
			
			XCTAssert((result.column(named: "someText") as String) == testText)
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
	
	
	static var allTests : [(String, (DatabaseTests) -> () throws -> Void)] {
		return [
			("testOnDiskDatabse", testOnDiskDatabase),
			("testBasicQuery", testBasicQuery),
		]
	}
}
