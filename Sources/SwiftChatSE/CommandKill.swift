//
//  CommandKill.swift
//  FireAlarm
//
//  Created by NobodyNada on 9/30/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation

open class CommandKill: Command {
	override open class func usage() -> [String] {
		return ["kill"]
	}
	
	override open class func privileges() -> ChatUser.Privileges {
		return [.owner]
	}
	
	override open func run() throws {
		abort()
	}
}
