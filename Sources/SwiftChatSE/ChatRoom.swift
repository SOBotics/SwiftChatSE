//
//  ChatRoom.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/27/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation
import Dispatch

///A ChatRoom represents a Stack Exchange chat room.
open class ChatRoom: NSObject {
    //MARK: - Instance variables
    
    ///A type of event from the chat room.
    public enum ChatEvent: Int {
        ///Caused when a message is posted in the chat room
        case messagePosted = 1
        ///Caused when a message is edited in the chat room
        case messageEdited = 2
        ///Caused when a user entered the chat room
        case userEntered = 3
        ///Caused when a user leaves the chat room
        case userLeft = 4
        ///Caused when the name of the room is changed
        case roomNameChanged = 5
        ///Caused when a message is stsrred in the chat room
        case messageStarred = 6
        case debugMessage = 7
        ///Caused when a user is mentioned in the chat room
        case userMentioned = 8
        ///Caused when a message is flagged in the chat room
        case messageFlagged = 9
        ///Caused when a message is deleted in the chat room
        case messageDeleted = 10
        ///Caused when a file is uploaded in the chat room
        case fileAdded = 11
        ///Caused when a message is mod flagged in the chat room
        case moderatorFlag = 12
        case userSettingsChanged = 13
        case globalNotification = 14
        case accessLevelChanged = 15
        case userNotification = 16
        ///Caused when a user is invited to a chat room
        case invitation = 17
        ///Caused when a message is replied to in a chat room
        case messageReply = 18
        ///Caused when a Room Owner moves a message to another room
        case messageMovedOut = 19
        ///Caused when a Room Owner moves a message to the room
        case messageMovedIn = 20
        ///Caused when the room is placed in timeout
        case timeBreak = 21
        case feedTicker = 22
        ///Caused when a user is suspended
        case userSuspended = 29
        ///Caused when a user is merged
        case userMerged = 30
        ///Caused when a user's username has changed
        case usernameChanged = 34
    };
    
    ///The host the bot is running on.
    public enum Host: Int {
        ///Used when the bot is running on 'stackoverflow.com'
        case stackOverflow
        ///Used when the bot is running on 'stackexchange.com'
        case stackExchange
        ///Used when the bot is running on 'meta.stackexchange.com'
        case metaStackExchange
        
        ///Returns the domain for the specified host
        public var domain: String {
            switch self {
            case .stackOverflow:
                return "stackoverflow.com"
            case .stackExchange:
                return "stackexchange.com"
            case .metaStackExchange:
                return "meta.stackexchange.com"
            }
        }
        
        ///Returns the chat domain for the specified host
        public var chatDomain: String {
            return "chat." + domain
        }
        
        ///Returns the domain URL for the host
        public var url: URL {
            return URL(string: "https://" + domain)!
        }
        
        ///Returns the URL for the chat host
        public var chatHostURL: URL {
            return URL(string: "https://" + chatDomain)!
        }
    }
    
    ///The Client to use.
    open let client: Client
    
    ///The ID of this room.
    open let roomID: Int
    
    ///The Host of this room.
    open let host: Host
    
    ///The list of known users.
    open var userDB = [ChatUser]()
    
    
    ///The fkey used to authorize actions in chat.
    open var fkey: String! {
        if _fkey == nil {
            //Get the chat fkey.
            let joinFavorites: String = try! client.get("https://\(host.chatDomain)/chats/join/favorite")
            
            guard let inputIndex = joinFavorites.range(of: "type=\"hidden\"")?.upperBound else {
                fatalError("Could not find fkey")
            }
            let input = String(joinFavorites[inputIndex...])
            
            guard let fkeyStartIndex = input.range(of: "value=\"")?.upperBound else {
                fatalError("Could not find fkey")
            }
            let fkeyStart = String(input[fkeyStartIndex...])
            
            guard let fkeyEnd = fkeyStart.range(of: "\"")?.lowerBound else {
                fatalError("Could not find fkey")
            }
            
            
            _fkey = String(fkeyStart[..<fkeyEnd])
        }
        return _fkey
    }
    
    
    ///The closure to run when a message is posted or edited.
    open var messageHandler: (ChatMessage, Bool) -> () = {message, isEdit in}
    
    ///Runs a closure when a message is posted or edited.
    open func onMessage(_ handler: @escaping (ChatMessage, Bool) -> ()) {
        messageHandler = handler
    }
    
    ///Whether the bot is currently in the chat room.
    open private(set) var inRoom = false
    
    ///Messages that are waiting to be posted & their completion handlers.
    open var messageQueue = [(String, ((Int?) -> Void)?)]()
    
    ///Custom per-room persistent storage.  Must be serializable by JSONSerialization!
    open var info: [String:Any] = [:]
    
    
    private var _fkey: String!
    
    private var ws: WebSocket!
    private var wsRetries = 0
    private let wsMaxRetries = 10
    
    private var timestamp: Int = 0
    
    
    private var lastEvent: Date?
    
    private var pendingLookup = [ChatUser]()
    
    private let defaultUserDBFilename: String
    
    
    //MARK: - User management
    
    internal func lookupUserInformation() {
        do {
            if pendingLookup.isEmpty {
                return
            }
            
            print("Looking up \(pendingLookup.count) user\(pendingLookup.count == 1 ? "" : "s")...")
            let ids = pendingLookup.map {user in
                String(user.id)
            }
            
            let postData = [
                "ids" : ids.joined(separator: ","),
                "roomID" : "\(roomID)"
            ]
            
            var data: Data, response: HTTPURLResponse
            
            repeat {
                (data, response) = try client.post(
                    "https://\(host.chatDomain)/user/info",
                    postData
                )
            } while response.statusCode == 400
            
            let json = String(data: data, encoding: .utf8)!
            do {
                guard let results = try client.parseJSON(json) as? [String:Any] else {
                    throw EventError.jsonParsingFailed(json: json)
                }
                
                guard let users = results["users"] as? [Any] else {
                    throw EventError.jsonParsingFailed(json: json)
                }
                
                for obj in users {
                    guard let user = obj as? [String:Any] else {
                        throw EventError.jsonParsingFailed(json: json)
                    }
                    
                    guard let id = user["id"] as? Int else {
                        throw EventError.jsonParsingFailed(json: json)
                    }
                    guard let name = user["name"] as? String else {
                        throw EventError.jsonParsingFailed(json: json)
                    }
                    
                    let isMod = (user["is_moderator"] as? Bool) ?? false
                    
                    //if user["is_owner"] is an NSNull, the user is NOT an owner.
                    let isRO = (user["is_owner"] as? NSNull) == nil ? true : false
                    
                    let chatUser = userWithID(id)
                    chatUser.name = name
                    chatUser.isMod = isMod
                    chatUser.isRO = isRO
                }
            } catch {
                handleError(error, "while looking up \(pendingLookup.count) users (json: \(json), request: \(String(urlParameters: postData)))")
            }
            pendingLookup.removeAll()
        }
        catch {
            handleError(error, "while looking up \(pendingLookup)")
        }
    }
    
    
    ///Looks up a user by ID.  If the user is not in the database, they are added.
    open func userWithID(_ id: Int) -> ChatUser {
        for user in userDB {
            if user.id == id {
                return user
            }
        }
        let user = ChatUser(room: self, id: id)
        userDB.append(user)
        if id == 0 {
            user.name = "Console"
        }
        else {
            pendingLookup.append(user)
        }
        return user
    }
    
    
    ///Looks up a user by name.  The user must already exist in the database!
    open func userNamed(_ name: String) -> [ChatUser] {
        var users = [ChatUser]()
        for user in userDB {
            if user.name == name {
                users.append(user)
            }
        }
        return users
    }
    
    
    ///Loads the user database from disk.
    ///- parameter filename: The filename to load the user databse from.
    ///The default value is `users_roomID_host.json`, for example `users_11347_stackoverflow.com.json` for SOBotics.
    open func loadUserDB(filename: String? = nil) throws {
        let file = filename ?? defaultUserDBFilename
        guard let data = try? Data(contentsOf: saveFileNamed(file)) else {
            return
        }
        guard let db = try JSONSerialization.jsonObject(with: data, options: []) as? [String:Any] else {
            return
        }
        
        info = (db["info"] as? [String:Any]) ?? [:]
        
        guard let dbUsers = db["users"] as? [Any] else {
            return
        }
        
        userDB = []
        var users = userDB
        
        for item in dbUsers {
            guard let info = (item as? [String:Any]) else {
                continue
            }
            guard let id = info["id"] as? Int else {
                continue
            }
            
            let user = userWithID(id)
            user.info = (info["info"] as? [String:Any]) ?? [:]
            user.privileges = (info["privileges"] as? Int).map { ChatUser.Privileges(rawValue: UInt($0)) } ?? []
            
            users.append(user)
        }
        
        userDB = users
    }
    
    ///Saves the user database to disk.
    ///- parameter filename: The filename to save the user databse to.
    ///The default value is `users_roomID_host.json`, for example `users_11347_stackoverflow.com.json` for SOBotics.
    open func saveUserDB(filename: String? = nil) throws {
        let file = filename ?? defaultUserDBFilename
        let db: Any
        db = userDB.map {
            [
                "id":$0.id,
                "info":$0.info,
                "privileges":$0.privileges.rawValue
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["info":info, "users":db], options: .prettyPrinted)
        try data.write(to: saveFileNamed(file), options: [.atomic])
    }
    
    
    
    
    ///Initializes a ChatRoom.
    ///- parameter client: The Client to use.
    ///- parameter roomID: The ID of the chat room.
    public init(client: Client, host: Host, roomID: Int) {
        self.client = client
        self.host = host
        self.roomID = roomID
        defaultUserDBFilename = "room_\(roomID)_\(host.domain).json"
    }
    
    
    
    
    fileprivate func messageQueueHandler() {
        while messageQueue.count != 0 {
            var result: String? = nil
            let text = messageQueue[0].0
            let completion = messageQueue[0].1
            do {
                let (data, response) = try client.post(
                    "https://\(host.chatDomain)/chats/\(roomID)/messages/new",
                    ["text":text, "fkey":fkey]
                )
                if response.statusCode == 400 {
                    print("Server error while posting message")
                }
                else {
                    result = String(data: data, encoding: .utf8)
                }
            }
            catch {
                handleError(error)
            }
            do {
                if let json = result {
                    if let data = try client.parseJSON(json) as? [String:Any] {
                        if let id = data["id"] as? Int {
                            messageQueue.removeFirst()
                            
                            completion?(id)
                        }
                        else {
                            print("Could not post duplicate message")
                            if !messageQueue.isEmpty {
                                messageQueue.removeFirst()
                                
                                completion?(nil)
                            }
                        }
                    }
                    else {
                        print(json)
                    }
                }
            }
            catch {
                if let r = result {
                    if r.hasPrefix("This room has been frozen") {
                        print("Could not post message to a frozen room")
                        if !messageQueue.isEmpty {
                            messageQueue.removeFirst()
                            
                            completion?(nil)
                        }
                    } else {
                        print(r)
                    }
                }
                else {
                    handleError(error)
                }
            }
            sleep(1)
        }
    }
    
    
    
    ///Posts a message to the ChatRoom.
    ///- paramter message: The content of the message to post, in Markdown.
    ///- parameter completion: The completion handler to call when the message is posted.
    ///The message ID will be passed to the completion handler.
    open func postMessage(_ message: String, completion: ((Int?) -> Void)? = nil) {
        if message.count == 0 {
            return
        }
        messageQueue.append((message, completion))
        if messageQueue.count == 1 {
            DispatchQueue.global().async {
                self.messageQueueHandler()
            }
        }
    }
    
    ///Replies to a ChatMessage.
    ///- paramter reply: The content of the message to post, in Markdown.
    ///- parameter to: The message ID to reply to.
    ///- parameter username: The name of the user who posted the message to reply to.
    ///                      If present, will be used as a fallback if the message ID is not present.
    ///
    ///- parameter completion: The completion handler to call when the message is posted.
    ///The message ID will be passed to the completion handler.
    open func postReply(_ reply: String, to messageID: Int?, username: String? = nil, completion: ((Int?) -> Void)? = nil) {
        if let id = messageID {
            postMessage(":\(id) \(reply)", completion: completion)
        } else if let name = username {
            postMessage("@\(name) \(reply)", completion: completion)
        } else {
            postMessage(reply)
        }
    }
    
    ///Replies to a ChatMessage.
    ///- paramter reply: The content of the message to post, in Markdown.
    ///- parameter to: The ChatMessage to reply to.
    ///- parameter completion: The completion handler to call when the message is posted.
    ///The message ID will be passed to the completion handler.
    open func postReply(_ reply: String, to: ChatMessage, completion: ((Int?) -> Void)? = nil) {
        postReply(reply, to: to.id, username: to.user.name, completion: completion)
    }
    
    
    ///An error that can occur while deleting a message
    enum DeletionError: Error {
        ///The ChatMessage's ID was nil.
        case noMessageID
        
        ///This user is not allowed to delete this message.
        case notAllowed
        
        ///It is past the 2-minute deadline for deleting messages.
        case tooLate
        
        ///An unknown error was returned.
        case unknownError(result: String)
    }
    
    open func delete(_ messageID: Int) throws {
        var retry = false
        
        repeat {
            if retry { sleep(1) }
            
            let result: String = try client.post("https://\(host.chatDomain)/messages/\(messageID)/delete", ["fkey":fkey])
            
            switch result.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
            case "ok":
                break
            case "It is too late to delete this message":
                throw DeletionError.tooLate
            case "You can only delete your own messages":
                throw DeletionError.notAllowed
            default:
                if result.hasPrefix("You can perform this action again in") {
                    retry = true
                } else {
                    throw DeletionError.unknownError(result: result)
                }
            }
        } while retry
    }
    
    ///Deletes a `ChatMessage`.
    
    open func delete(_ message: ChatMessage) throws {
        guard let id = message.id else { throw DeletionError.noMessageID }
        try delete(id)
    }
    
    
    ///Joins the chat room.
    open func join() throws {
        print("Joining chat room \(roomID)...")
        
        try connectWS()
        
        let _ = userWithID(0)   //add the Console to the database
        let json: String = try client.get("https://\(host.chatDomain)/rooms/pingable/\(roomID)")
        guard let users = try client.parseJSON(json) as? [Any] else {
            throw EventError.jsonParsingFailed(json: json)
        }
        
        for userObj in users {
            guard let user = userObj as? [Any] else {
                throw EventError.jsonParsingFailed(json: json)
            }
            guard let userID = user[0] as? Int else {
                throw EventError.jsonParsingFailed(json: json)
            }
            let _ = userWithID(userID)
        }
        
        print("Users in database: \((userDB.map {$0.description}).joined(separator: ", "))")
        
        inRoom = true
        
    }
    
    
    ///Leaves the chat room.
    open func leave() {
        //we don't really care if this fails
        //...right?
        
        //Checking if the bot has already left the room
        guard inRoom else { return }
        
        inRoom = false
        let _ = try? client.post("https://\(host.chatDomain)/chats/leave/\(roomID)", ["quiet":"true","fkey":fkey]) as String
        ws.disconnect()
        for _ in 0..<10 {
            if ws.state == .disconnecting {
                sleep(1)
            }
        }
    }
    
    ///The errors which can be caused while the bot joins the room.
    public enum RoomJoinError: Error {
        ///When the retrieval of information for a room failed.
        case roomInfoRetrievalFailed
    }
    
    fileprivate func connectWS() throws {
        //get the timestamp
        guard let time = (try client.parseJSON(client.post("https://\(host.chatDomain)/chats/\(roomID)/events", [
            "roomid" : String(roomID),
            "fkey": fkey
            ])) as? [String:Any])?["time"] as? Int else {
                throw RoomJoinError.roomInfoRetrievalFailed
        }
        timestamp = time
        
        //get the auth code
        let wsAuth = try client.parseJSON(
            client.post("https://\(host.chatDomain)/ws-auth", ["roomid":String(roomID), "fkey":fkey]
            )
            ) as! [String:Any]
        
        let wsURL = (wsAuth["url"] as! String)
        
        let url = URL(string: "\(wsURL.replacingOccurrences(of: "wss:", with: "ws:"))?l=\(timestamp)")!
        //var request = URLRequest(url: url)
        
        //request.setValue("https://chat.\(client.host.rawValue)", forHTTPHeaderField: "Origin")
        //for (header, value) in client.cookieHeaders(forURL: url) {
        //	request.setValue(value, forHTTPHeaderField: header)
        //}
        
        //ws = WebSocket(request: request)
        var headers = ""
        for (header, value) in client.cookieHeaders(forURL: url) {
            headers += "\(header): \(value)\u{0d}\u{0a}"
        }
        
        #if os(Linux)
        let origin = host.chatDomain
        #else
        let origin = "http://\(host.chatDomain)"
        #endif
        
        ws = try WebSocket.open(url, origin: origin, headers: headers)
        //ws.eventQueue = client.queue
        //ws.delegate = self
        //ws.open()
        
        ws.onOpen {socket in
            self.webSocketOpen()
        }
        ws.onText {socekt, text in
            self.webSocketMessageText(text)
        }
        ws.onBinary {socket, data in
            self.webSocketMessageData(data)
        }
        ws.onClose {socket in
            self.webSocketEnd(0, reason: "", wasClean: true, error: socket.error)
        }
        ws.onError {socket in
            self.webSocketEnd(0, reason: "", wasClean: true, error: socket.error)
        }
    }
    
    ///An error which happened while the bot was processing a chat event.
    public enum EventError: Error {
        ///This is caused when the library cannot parse the specified json.
        case jsonParsingFailed(json: String)
        ///This is caused when the chat room event type is invalid.
        case invalidEventType(type: Int)
    }
    
    func handleEvents(_ events: [Any]) throws {
        for e in events {
            guard let event = e as? [String:Any] else {
                throw EventError.jsonParsingFailed(json: String(describing: events))
            }
            guard let typeCode = event["event_type"] as? Int else {
                throw EventError.jsonParsingFailed(json: String(describing: events))
            }
            guard let type = ChatEvent(rawValue: typeCode) else {
                throw EventError.invalidEventType(type: typeCode)
            }
            
            switch type {
            case .messagePosted, .messageEdited:
                guard
                    let userID = event["user_id"] as? Int,
                    let messageID = event["message_id"] as? Int,
                    let rendered = (event["content"] as? String)?.stringByDecodingHTMLEntities else {
                        throw EventError.jsonParsingFailed(json: String(describing: events))
                }
                
                var replyID: Int? = nil
                
                var content: String = try client.get("https://\(host.chatDomain)/message/\(messageID)?plain=true")
                
                if let parent = event["parent_id"] as? Int {
                    replyID = parent
                    //replace the reply markdown with the rendered ping
                    var components = content.components(separatedBy: .whitespaces)
                    let renderedComponents = rendered.components(separatedBy: .whitespaces)
                    
                    if !components.isEmpty && !rendered.isEmpty {
                        components[0] = renderedComponents[0]
                        content = components.joined(separator: " ")
                    }
                }
                
                //look up the user instead of getting their name to make sure they're in the DB
                let user = userWithID(userID)
                
                print("\(roomID): \(user): \(content)")
                
                let message = ChatMessage(room: self, user: user, content: content, id: messageID, replyID: replyID)
                messageHandler(message, type == .messageEdited)
            default:
                break
            }
        }
    }
    
    
    
    
    //MARK: - WebSocket methods
    
    private func webSocketOpen() {
        print("Websocket opened!")
        //let _ = try? ws.write("hello")
        wsRetries = 0
        DispatchQueue.global().async {
            sleep(5)	//asyncAfter doesn't seem to work on Linux
            if self.lastEvent == nil {
                self.ws.disconnect()
                return
            }
            
            while true {
                sleep(600)
                if Date().timeIntervalSinceReferenceDate - self.lastEvent!.timeIntervalSince1970 > 600 {
                    self.ws.disconnect()
                    return
                }
            }
        }
    }
    
    private func webSocketMessageText(_ text: String) {
        lastEvent = Date()
        do {
            guard let json = try client.parseJSON(text) as? [String:Any] else {
                throw EventError.jsonParsingFailed(json: text)
            }
            
            if (json["action"] as? String) == "hb" {
                //heartbeat
                ws.write("{\"action\":\"hb\",\"data\":\"hb\"}")
                return
            }
            
            let roomKey = "r\(roomID)"
            guard let events = (json[roomKey] as? [String:Any])?["e"] as? [Any] else {
                return  //no events
            }
            
            try handleEvents(events)
        }
        catch {
            handleError(error, "while parsing events")
        }
    }
    
    private func webSocketMessageData(_ data: Data) {
        print("Recieved binary data: \(data)")
    }
    
    private func attemptReconnect() {
        var done = false
        repeat {
            do {
                if wsRetries >= wsMaxRetries {
                    fatalError("Failed to reconnect websocket!")
                }
                wsRetries += 1
                try connectWS()
                done = true
            } catch {
                done = false
            }
        } while !done
    }
    
    private func webSocketEnd(_ code: Int, reason: String, wasClean: Bool, error: Error?) {
        if let e = error {
            print("Websocket error:\n\(e)")
        }
        else {
            print("Websocket closed")
        }
        
        if inRoom {
            print("Trying to reconnect...")
            attemptReconnect()
        }
    }
    
}
