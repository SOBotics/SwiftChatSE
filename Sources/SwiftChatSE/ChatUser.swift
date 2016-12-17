//
//  ChatUser.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/28/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation


///A ChatUser represents a user on Stack Exchange chat.
open class ChatUser: CustomStringConvertible {
	
	///The user ID.
    open let id: Int
    
    fileprivate var _name: String?
    fileprivate var _isMod: Bool?
    fileprivate var _isRO: Bool?
	
	///Custom per-user persistent storage.  Must be serializable by JSONSerialization!
	open var info: [String:Any] = [:]
	
	///Privileges of a ChatUser.  Privileges can be added by extending this struct and adding static properties.
	public struct Privileges: OptionSet {
		public let rawValue: UInt
		
		public init(rawValue: Privileges.RawValue) {
			self.rawValue = rawValue
		}
		
		///Owners of the chat bot.
		public static let owner = Privileges(rawValue: 1 << 0)
		
		
		///The names of these privileges.
		public var names: [String] {
			var raw = rawValue
			var shifts = 0
			var result = [String]()
			
			
			while raw != 0 {
				let priv = Privileges(rawValue: (raw << Privileges.RawValue(shifts)) & Privileges.RawValue(1 << shifts))
				if priv.rawValue != 0 {
					result.append(Privileges.name(of: priv))
				}
				
				raw >>= 1
				shifts += 1
			}
			
			
			return result
		}
		
		
		
		
		///Registers a name for a privilege.
		public static func add(name: String, for privilege: Privileges) {
			assertOne(privilege)
			privilegeNames[privilege.rawValue] = name
		}
		
		
		///Returns the name of a privilege.
		public static func name(of privilege: Privileges) -> String {
			assertOne(privilege)
			return privilegeNames[privilege.rawValue] ?? "<unnamed privilege>"
		}
		
		
		
		
		
		public private(set) static var privilegeNames: [Privileges.RawValue:String] = { [owner.rawValue:"Owner"] }()
		
		private static func assertOne(_ privileges: Privileges) {
			//count the number of ones in the binary representation of privilege's raw value
			var raw = privileges.rawValue
			var ones = 0
			
			while raw != 0 {
				if (raw & 1) != 0 {
					ones += 1
				}
				raw >>= 1
			}
			
			if ones != 1 {
				fatalError("privilege must contain exactly one privilege")
			}
		}
	}
	
	
	///The name of this user.
    open var name: String {
        get {
            if let n = _name {
                return n
			} else if id == 0 {
				return "Console"
			} else {
                room.lookupUserInformation()
                return _name ?? "<unkown user \(id)>"
            }
        }
        set {
            _name = newValue
        }
    }
	
	///Whether this user is a ♦ moderator.
    open var isMod: Bool {
        get {
            if let i = _isMod {
                return i
			} else if id == 0 {
				return false
			} else {
                room.lookupUserInformation()
                return _isMod ?? false
            }
        }
        set {
            _isMod = newValue
        }
    }
	
	///Whether this user is an owner of the room.
    open var isRO: Bool {
        get {
            if let i = _isRO {
                return i
			} else if id == 0 {
				return false
			} else {
                room.lookupUserInformation()
                return _isRO ?? false
            }
        }
        set {
            _isRO = newValue
        }
    }
    
    open var description: String {
        return name
    }
	
	
	///The privileges this user has.
	open var privileges: Privileges = []
	
	
	///The room this user is from.
    open let room: ChatRoom
	
	
	
    public init(room: ChatRoom, id: Int, name: String? = nil) {
        self.room = room
        self.id = id
        _name = name
    }
	
	
	///Whether the user has the specified privileges.
	///- note: Room owners, moderators, and the Console user implicitly have all privileges.
	public func has(privileges required: Privileges) -> Bool {
		return isMod || isRO || id == 0 || privileges.isSuperset(of: required)
	}
	
	///Returns the specified privilege that this user is missing.
	///- note: Room owners, moderators, and the Console user implicitly have all privileges.
	public func missing(from required: Privileges) -> Privileges {
		return (isMod || isRO || id == 0) ? [] : privileges.subtracting(required)
	}
}
