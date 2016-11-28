//
//  CommandListRunning.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/28/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation

open class CommandListRunning: Command {
    override open class func usage() -> [String] {
        return ["running commands"]
    }
    
    override open func run() throws {
        var users = [String]()
        var commands = [String]()
        for command in listener.runningCommands {
            users.append("\(command.message.user.name)")
            commands.append("\(command.message.content)")
        }
        
        reply("Running commands:")
        message.room.postMessage(makeTable(["User", "Command"], contents: users, commands))
    }
}
