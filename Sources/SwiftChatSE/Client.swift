//
//  Client.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/27/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//
//TODO: Refactor this class; it's kind of a mess.

import Foundation
import Dispatch

#if os(Linux)
import FoundationNetworking
#endif

//MARK: - Convenience extensions

extension String {
    var urlEncodedString: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        return self.addingPercentEncoding(withAllowedCharacters: allowed)!
    }
    
    init(urlParameters: [String:String]) {
        var result = [String]()
        
        for (key, value) in urlParameters {
            result.append("\(key.urlEncodedString)=\(value.urlEncodedString)")
        }
        
        self.init(result.joined(separator: "&"))
    }
}

func + <K, V> (left: [K:V], right: [K:V]) -> [K:V] {
    var result = left
    for (k, v) in right {
        result[k] = v
    }
    return result
}

//https://stackoverflow.com/a/24052094/3476191
func += <K, V> (left: inout [K:V], right: [K:V]) {
    for (k, v) in right {
        left[k] = v
    }
}

//MARK: -
///A Client handles HTTP requests, cookie management, and logging in to Stack Exchange chat.
open class Client: NSObject, URLSessionDataDelegate {
    //MARK: Instance variables
    open var session: URLSession {
        return URLSession(
            configuration: configuration,
            delegate: self, delegateQueue: delegateQueue
        )
    }
    ///Pretty self explanatory
    open var cookies = [HTTPCookie]()
    private let queue = DispatchQueue(label: "Client queue")
    
    ///Indicates whether the client is logged in or not.
    open var loggedIn = false
    
    private var configuration: URLSessionConfiguration
    private var delegateQueue: OperationQueue
    
    ///Errors which can happen while making a request
    public enum RequestError: Error {
        case invalidURL(url: String)
        case notUTF8
        case unknownError
        case timeout
    }
    
    ///Indicates the duration of a timeout
    open var timeoutDuration: TimeInterval = 30
    
    //MARK: - Private variables
    private class HTTPTask {
        var task: URLSessionTask
        var completion: (Data?, HTTPURLResponse?, Error?) -> Void
        
        var data: Data?
        var response: HTTPURLResponse?
        var error: Error?
        
        init(task: URLSessionTask, completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
            self.task = task
            self.completion = completion
        }
    }
    
    private var tasks = [URLSessionTask:HTTPTask]()
    
    private var responseSemaphore: DispatchSemaphore?
    
    
    
    //MARK: - Cookie handling
    private func processCookieDomain(domain: String) -> String {
        return URL(string: domain)?.host ?? domain
    }
    
    ///Prints all of the cookies, for debugging.
    private func printCookies(_ cookies: [HTTPCookie]) {
        print(cookies.map { "\($0.domain)::\($0.name)::\($0.value)" }.joined(separator: "\n") + "\n\n")
    }
    
    
    
    ///Adds cookies.
    ///- parameter newCookies: The cookies to add.
    ///- parameter host: The host which set the cookies..
    open func addCookies(_ newCookies: [HTTPCookie], forHost host: String) {
        let toAdd = newCookies.map {cookie -> HTTPCookie in
            var properties = cookie.properties ?? [:]
            properties[HTTPCookiePropertyKey.domain] = processCookieDomain(domain: cookie.domain)
            return HTTPCookie(properties: properties) ?? cookie
        }
        
        //print("Adding:")
        //printCookies(newCookies)
        
        for cookie in toAdd {    //for each cookie to add...
            if let index = cookies.index(where: {
                $0.name == cookie.name && cookieHost(host, matchesDomain: $0.domain)
            }) {
                //if this cookie needs to be replaced, replace it
                cookies[index] = cookie
            } else {
                cookies.append(cookie)
            }
        }
        
        //print("Cookies:")
        //printCookies(cookies)
    }
    
    
    
    ///Checks whether a cookie matches a domain.
    ///- parameter host: The host of the cookie.
    ///- parameter domain: The domain.
    open func cookieHost(_ host: String, matchesDomain domain: String) -> Bool {
        let hostFields = host.components(separatedBy: ".")
        var domainFields = domain.components(separatedBy: ".")
        if hostFields.count == 0 || domainFields.count == 0 {
            return false
        }
        
        if domainFields.first!.isEmpty {
            domainFields.removeFirst()
        }
        
        //if the domain starts with a dot, match any host which is a subdomain of domain
        var hostIndex = hostFields.count - 1
        for i in (0...domainFields.count - 1).reversed() {
            if hostIndex == 0 && i != 0 {
                return false
            }
            if domainFields[i] != hostFields[hostIndex] {
                return false
            }
            
            hostIndex -= 1
        }
        return true
    }
    
    
    
    ///Returns the cookie headers for the specified URL.
    open func cookieHeaders(forURL url: URL) -> [String:String] {
        return HTTPCookie.requestHeaderFields(with: cookies.filter {
            cookieHost(url.host ?? "", matchesDomain: $0.domain)
        })
    }
    
    
    //MARK: - URLSession delegate methods
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        
        guard let task = tasks[dataTask] else {
            print("\(dataTask) is not in client task list; cancelling")
            completionHandler(.cancel)
            return
        }
        
        var headers = [String:String]()
        for (k, v) in (response as? HTTPURLResponse)?.allHeaderFields ?? [:] {
            headers[String(describing: k)] = String(describing: v)
        }
        
        let url = response.url ?? URL(fileURLWithPath: "<invalid>")
        
        addCookies(HTTPCookie.cookies(withResponseHeaderFields: headers, for: url), forHost: url.host ?? "")
        
        task.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let task = tasks[dataTask] else {
            print("\(dataTask) is not in client task list; ignoring")
            return
        }
        
        if task.data != nil {
            task.data!.append(data)
        }
        else {
            task.data = data
        }
    }
    
    public func urlSession(_ session: URLSession, task sessionTask: URLSessionTask, didCompleteWithError error: Error?) {
        guard let task = tasks[sessionTask] else {
            print("\(sessionTask) is not in client task list; ignoring")
            return
        }
        task.error = error
        
        task.completion(task.data, task.response, task.error)
        
        tasks[sessionTask] = nil
    }
    
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
        ) {
        
        var headers = [String:String]()
        for (k, v) in response.allHeaderFields {
            headers[String(describing: k)] = String(describing: v)
        }
        
        let url = response.url ?? URL(fileURLWithPath: "invalid")
        addCookies(HTTPCookie.cookies(withResponseHeaderFields: headers, for: url), forHost: url.host ?? "")
        
        var request = request
        let newURL = request.url ?? URL(fileURLWithPath: ("invalid"))
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        for (key, val) in cookieHeaders(forURL: newURL) {
            request.addValue(val, forHTTPHeaderField: key)
        }
        completionHandler(request)
    }
    
    private func performTask(_ task: URLSessionTask, completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
        tasks[task] = HTTPTask(task: task, completion: completion)
        task.resume()
    }
    
    
    
    //MARK:- Request methods.
    
    ///Performs an `URLRequest`.
    ///- parameter request: The request to perform.
    ///- returns: The `Data` and `HTTPURLResponse` returned by the request.
    open func performRequest(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        var req = request
        
        let sema = DispatchSemaphore(value: 0)
        var data: Data!
        var resp: URLResponse!
        var error: Error!
        
        let url = req.url ?? URL(fileURLWithPath: ("invalid"))
        
        for (key, val) in cookieHeaders(forURL: url) {
            req.addValue(val, forHTTPHeaderField: key)
        }
        
        queue.async {
            let task = self.session.dataTask(with: req)
            self.performTask(task) {inData, inResp, inError in
                (data, resp, error) = (inData, inResp, inError)
                sema.signal()
            }
        }
        
        
        if sema.wait(timeout: DispatchTime.now() + timeoutDuration) == .timedOut {
            error = RequestError.timeout
        }
        
        guard let response = resp as? HTTPURLResponse, data != nil else {
            throw error
        }
        
        return (data, response)
    }
    
    
    
    ///Performs a GET request.
    ///- paramter url: The URL to make the request to.
    ///- returns: The `Data` and `HTTPURLResponse` returned by the request.
    open func get(_ url: String) throws -> (Data, HTTPURLResponse) {
        guard let nsUrl = URL(string: url) else {
            throw RequestError.invalidURL(url: url)
        }
        var request = URLRequest(url: nsUrl)
        request.setValue(String(request.httpBody?.count ?? 0), forHTTPHeaderField: "Content-Length")
        return try performRequest(request)
    }
    
    ///Performs a POST request.
    ///- parameter url: The URL to make the request to.
    ///- parameter data: The body of the POST request.
    ///- returns: The `Data` and `HTTPURLResponse` returned by the request.
    open func post(_ url: String, data: Data, contentType: String? = nil) throws -> (Data, HTTPURLResponse) {
        guard let nsUrl = URL(string: url) else {
            throw RequestError.invalidURL(url: url)
        }
        
        let contentType = contentType ?? "application/x-www-form-urlencoded"
        
        var request = URLRequest(url: nsUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        
        let url = request.url ?? URL(fileURLWithPath: ("invalid"))
        for (key, val) in cookieHeaders(forURL: url) {
            request.addValue(val, forHTTPHeaderField: key)
        }
        
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        
        let sema = DispatchSemaphore(value: 0)
        
        var responseData: Data?
        var resp: HTTPURLResponse?
        var responseError: Error?
        
        queue.async {
            let task = self.session.uploadTask(with: request, from: data)
            self.performTask(task) {data, response, error in
                (responseData, resp, responseError) = (data, response, error)
                sema.signal()
            }
        }
        
        if sema.wait(timeout: DispatchTime.now() + timeoutDuration) == .timedOut {
            responseError = RequestError.timeout
        }
        
        
        guard let response = resp else {
            throw responseError ?? RequestError.unknownError
        }
        
        if responseData == nil {
            responseData = Data()
        }
        
        return (responseData!, response)
    }
    
    
    ///Performs a POST request.
    ///- parameter url: The URL to make the request to.
    ///- parameter data: The fields to include in the POST request.
    ///- returns: The `Data` and `HTTPURLResponse` returned by the request.
    open func post(_ url: String, _ data: [String:String]) throws -> (Data, HTTPURLResponse) {
        guard let data = String(urlParameters: data).data(using: String.Encoding.utf8) else {
            throw RequestError.notUTF8
        }
        
        return try post(url, data: data)
    }
    
    
    
    ///Performs an URLRequest.
    ///- parameter request: The request to perform.
    ///- returns: The UTF-8 string returned by the request.
    open func performRequest(_ request: URLRequest) throws -> String {
        let (data, _) = try performRequest(request)
        guard let string = String(data: data, encoding: String.Encoding.utf8) else {
            throw RequestError.notUTF8
        }
        return string
    }
    
    
    
    ///Performs a GET request.
    ///- paramter url: The URL to make the request to.
    ///- returns: The UTF-8 string returned by the request.
    open func get(_ url: String) throws -> String {
        let (data, _) = try get(url)
        guard let string = String(data: data, encoding: String.Encoding.utf8) else {
            throw RequestError.notUTF8
        }
        return string
    }
    
    
    ///Performs a POST request.
    ///- parameter url: The URL to make the request to.
    ///- parameter data: The fields to include in the POST request.
    ///- returns: The UTF-8 string returned by the request.
    open func post(_ url: String, _ fields: [String:String]) throws -> String {
        let (data, _) = try post(url, fields)
        guard let string = String(data: data, encoding: String.Encoding.utf8) else {
            throw RequestError.notUTF8
        }
        return string
    }
    
    
    ///Performs a POST request.
    ///- parameter url: The URL to make the request to.
    ///- parameter data: The body of the POST request.
    ///- returns: The UTF-8 string returned by the request.
    open func post(_ url: String, data: Data, contentType: String? = nil) throws -> String {
        let (data, _) = try post(url, data: data, contentType: contentType)
        guard let string = String(data: data, encoding: String.Encoding.utf8) else {
            throw RequestError.notUTF8
        }
        return string
    }
    
    
    
    ///Parses a JSON string.
    open func parseJSON(_ json: String) throws -> Any {
        return try JSONSerialization.jsonObject(with: json.data(using: String.Encoding.utf8)!, options: .allowFragments)
    }
    
    
    
    
    //MARK: - Initializers and login.
    
    ///Initializes a Client.
    ///- parameter host: The chat host to log in to.
    override public init() {
        let configuration =  URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        self.configuration = configuration
        
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        self.delegateQueue = delegateQueue
        
        super.init()
        
        /*configuration.connectionProxyDictionary = [
            "HTTPEnable" : 1,
            kCFNetworkProxiesHTTPProxy as AnyHashable : "192.168.1.234",
            kCFNetworkProxiesHTTPPort as AnyHashable : 8080,
            
            "HTTPSEnable" : 1,
            kCFNetworkProxiesHTTPSProxy as AnyHashable : "192.168.1.234",
            kCFNetworkProxiesHTTPSPort as AnyHashable : 8080
        ]*/
    }
    
    ///Errors which can occur while logging in.
    public enum LoginError: Error {
        ///Occurs when the client is already logged in.
        case alreadyLoggedIn
        ///Occurs when the fkey required to log in is not found.
        case fkeyNotFound
        ///Occurs when a login fails.
        case loginFailed
    }
    
    
    ///Logs in to Stack Exchange.
    open func login(email: String, password: String) throws {
        if loggedIn {
            throw LoginError.alreadyLoggedIn
        }
        
        print("Logging in...")
        for host: ChatRoom.Host in [.stackOverflow, .metaStackExchange] {
            //Login to host.
            let hostLoginURL = "https://\(host.domain)/users/login"
            let hostLoginPage: String = try get(hostLoginURL)
            guard let fkey = getHiddenInputs(hostLoginPage)["fkey"] else {
                throw LoginError.fkeyNotFound
            }
            
            let (_, _) = try post(hostLoginURL, [
                "email" : email,
                "password" : password,
                "fkey" : fkey
                ]
            )
            
            if !cookies.contains(where: { $0.name == "acct" && cookieHost(host.domain, matchesDomain: $0.domain) }) {
                throw LoginError.loginFailed
            }
        }
    }
    
    
    fileprivate func getHiddenInputs(_ string: String) -> [String:String] {
        var result = [String:String]()
        
        let components = string.components(separatedBy: "<input type=\"hidden\"")
        
        for input in components[1..<components.count] {
            guard let nameStartIndex = input.range(of: "name=\"")?.upperBound else {
                continue
            }
            let nameStart = String(input[nameStartIndex...])
            
            guard let nameEndIndex = nameStart.range(of: "\"")?.lowerBound else {
                continue
            }
            let name = String(nameStart[..<nameEndIndex])
            
            guard let valueStartIndex = nameStart.range(of: "value=\"")?.upperBound else {
                continue
            }
            let valueStart = String(nameStart[valueStartIndex...])
            
            guard let valueEndIndex = valueStart.range(of: "\"")?.lowerBound else {
                continue
            }
            
            let value = String(valueStart[..<valueEndIndex])
            
            result[name] = value
        }
        
        return result
    }
    
    
}

