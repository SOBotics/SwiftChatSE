//
//  CommandDeleteMessage.swift
//  SwiftChatSE
//
//  Created by NobodyNada on 5/24/17.
//
//

import Foundation

open class CommandDeleteMessage: Command {
	override open class func usage() -> [String] {
		return ["del ...", "delete ...", "poof ...", "remove ...", "ninja'd ..."]
	}
	
	enum TranscriptURLParsingError: Error {
		case wrongHost
		case notChatMessage
	}
	
	private func parseTranscriptURL(_ url: URL) throws -> Int {
		guard url.host == message.room.host.chatDomain else {
			throw TranscriptURLParsingError.wrongHost
		}
		
		guard url.pathComponents.count > 2, url.pathComponents[1] == "transcript" else {
			throw TranscriptURLParsingError.notChatMessage
		}
		
		if let id = url.fragment.flatMap({Int($0)}) { return id }
		else if let id =
			URLComponents(url: url, resolvingAgainstBaseURL: true)?
				.queryItems?.first(where: {$0.name == "m"})?.value
				.flatMap({Int($0)}) { return id }
		else if let id = Int(url.pathComponents.last!) { return id }
		else { throw TranscriptURLParsingError.notChatMessage }
	}
	
	override open func run() throws {
		var ids = [Int]()
		do {
			//Get the message ID canidates.
			([
				//the raw message ID as arguments
                arguments.compactMap { Int($0) },
				
				//the transcript URL as arguments
				try arguments.compactMap {
					if let url = URL(string: $0), url.host != nil {
						return try parseTranscriptURL(url)
					} else { return nil }
				},
				
				//the reply ID
				[arguments.isEmpty ? message.replyID : nil].compactMap { $0 }
				
				] as [[Int]])
				.reduce([], +)
				.forEach {
					//remove duplicates
					if !ids.contains($0) { ids.append($0) }
			}
			
		} catch TranscriptURLParsingError.wrongHost {
			reply("I cannot delete messages on a different chat host.")
			return
		} catch TranscriptURLParsingError.notChatMessage {
			reply("That URL does not look like a link to a chat message.")
			return
		}
		
		
		if ids.isEmpty {
			reply("Which messages should be deleted?")
			return
		}
		
		
		do {
			for id in ids {
				try message.room.delete(id)
			}
		} catch ChatRoom.DeletionError.notAllowed {
			reply("I am not allowed to delete that message.")
		} catch ChatRoom.DeletionError.tooLate {
			reply("It is too late to delete that message.")
		}
	}
}
