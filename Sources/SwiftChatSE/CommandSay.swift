//
//  CommandSay.swift
//  FireAlarm
//
//  Created by NobodyNada on 10/1/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation

open class CommandSay: Command {
	override open class func usage() -> [String] {
		return ["say ..."]
	}
	
	override open func run() throws {
		message.room.postMessage(message.content.components(separatedBy: " ").dropFirst().dropFirst().joined(separator: " "))
	}
}
