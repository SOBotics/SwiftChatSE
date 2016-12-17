//
//  ChatMessage.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/28/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation

///A ChatMessage represents a message in Stack Exchange chat.
public struct ChatMessage {
	///The room in which this message was posted.
	public let room: ChatRoom
	
	///The user who posted this message.
    public let user: ChatUser
	
	///The content of this message.
    public let content: String
	
	///This message's ID, or `nil` if it is not known.
    public let id: Int?
	
	///The message that this message replied to, or `nil` if this message is not a reply.
	public let replyID: Int?
	
	
	public init(room: ChatRoom, user: ChatUser, content: String, id: Int?, replyID: Int? = nil) {
		self.room = room
        self.user = user
        self.content = content
        self.id = id
		self.replyID = replyID
    }
}
