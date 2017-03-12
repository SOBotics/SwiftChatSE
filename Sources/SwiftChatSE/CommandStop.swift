//
//  CommandStop.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/31/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation

open class CommandStop: Command {
    fileprivate let REBOOT_INDEX = 4
    override open class func usage() -> [String] {
        return ["stop ...", "halt ...", "shutdown ...", "shut down ...", "restart ...", "reboot ..."]
    }
	
	override open class func privileges() -> ChatUser.Privileges {
		return [.owner]
	}
    
    override open func run() throws {
        let action: ChatListener.StopReason
        let reply: String
        
        let argLocation: String
    
        if arguments.count == 0 {
            if usageIndex < REBOOT_INDEX {
                action = .halt
                reply = "Shutting down..."
            }
            else {
                action = .reboot
                reply = "Rebooting..."
            }
            
            self.reply(reply)
            listener.stop(action)
            
            return
        } else {
            argLocation = arguments [0].lowercased()
        }
        
        if (userLocation == "<unknown>")
        {
            self.reply ("Location is set to unknown!")
            return
        }
        
        //self.reply (argLocation)
        //self.reply (userLocation)
        
        if (userLocation.lowercased() == argLocation) {
            if usageIndex < REBOOT_INDEX {
                action = .halt
                reply = "Shutting down..."
            }
            else {
                action = .reboot
                reply = "Rebooting..."
            }
            
            self.reply(reply)
            listener.stop(action)
            
            return
        }
    }
}
