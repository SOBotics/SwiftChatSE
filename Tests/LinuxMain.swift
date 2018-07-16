import XCTest
@testable import SwiftChatSETests

XCTMain([
     testCase(ListenerTests.allTests),
	 testCase(DatabaseTests.allTests)
])
