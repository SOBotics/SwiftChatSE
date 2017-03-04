//
//  ErrorHandler.swift
//  FireAlarm
//
//  Created by NobodyNada on 11/22/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation
import Dispatch

public var errorRoom: ChatRoom?

public func errorAsNSError(_ error: Error) -> NSError? {
	#if os(Linux)
		//this is the only way I could find to check if an arbitrary Error is an NSError that doesn't crash on Linux
		//it produces a warning "'is' test is always true"
		return error is AnyObject ? unsafeBitCast(error, to: NSError.self) : nil
	#else
		return type(of: error) == NSError.self ? error as NSError : nil
	#endif
}

public func formatNSError(_ e: NSError) -> String {
	return "\(e.domain) code \(e.code) \(e.userInfo)"
}

///The maximum amount of errors that can occur in a 30-second period.
public var maxErrors = 2

///What to do after too many errors.  Defaults to calling `abort`.
public var afterTooManyErrors: () -> () = { abort() }

///How many errors have occured within the last 30 seconds.
public var errorsInLast30Seconds = 0

///A string that will be appended to the error message so that the bot's author can be pinged by errors..
public var ping = " (cc @AshishAhuja @NobodyNada)"

///Logs an error.
public func handleError(_ error: Error, _ context: String? = nil) {
	let contextStr: String
	let errorType: String
	let errorDetails: String
	
	#if os(Linux)
		if let e = errorAsNSError(error) {
			errorType = "NSError"
			errorDetails = formatNSError(e)
		} else {
			errorType = String(reflecting: type(of: error))
			errorDetails = String(describing: error)
		}
	#else
		errorType = String(reflecting: type(of: error))
		errorDetails = String(describing: error)
	#endif
	
	if context != nil {
		contextStr = " \(context!)"
	}
	else {
		contextStr = ""
	}
	
	let message1 = "    An error (\(errorType)) occured\(contextStr)\(ping):"
	
	if let room = errorRoom {
		room.postMessage(message1 + "\n    " + errorDetails.replacingOccurrences(of: "\n", with: "\n    "))
	}
	else {
		print("\(message1)\n\(errorDetails)")
		exit(1)
	}
	
	errorsInLast30Seconds += 1
	if errorsInLast30Seconds > maxErrors {
		afterTooManyErrors()
	}
	
	DispatchQueue.global(qos: .background).async {
		sleep(30)
		errorsInLast30Seconds -= 1
	}
}
