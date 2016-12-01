//
//  Post.swift
//  FireAlarm
//
//  Created by NobodyNada on 9/25/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

public struct Post {
	public let id: Int
	public let title: String
	public let body: String
	public let tags: [String]
	public let creationDate: Int
	public let lastActivityDate: Int
	public let userID: Int?
	public let username: String
}
