//
//  SocketServer.swift
//  MessageProxy
//
//  Created by Allison Husain on 5/5/17.
//  Copyright © 2017 Allison Husain. All rights reserved.
//

import Foundation
import KituraNet
import KituraWebSocket

class SocketServer : NSObject {
    var listeningUsers:[TCPClient] = []
    var passwordToken = ""
    
    /// Setup the socket server with a specific API protection token. This must be the same one if you're using AndromedaB
    ///
    /// - Parameter apiToken: The API token
    init(apiToken:String) {
        super.init()
        passwordToken = apiToken
        setupServer()
    }
    
    /// Create the server
    func setupServer() {
        let server = HTTP.createServer()
        server.delegate = ChatServerDelegate()
        
        do {
            try server.listen(on: 8080)
            ListenerGroup.waitForListeners()
        } catch {
            Log.error("Error listening on port 8080: \(error).")
        }
    }
    
    
    /// Authenticate a user and if they pass add them to our broadcast
    ///
    /// - Parameter client: The new client
    func authenticateClient(client:TCPClient)  {
        print("Awaiting token from \(client.address)[\(client.port)]")
        send(client: client, message: "OK\n")
        //Now let's wait for a token for only two seconds. If the client can't keep up they honestly don't deserve it
        let token = client.read(1024*10, timeout: 2)
        let stringToken = String(bytes: token ?? [], encoding: .utf8)?.replacingOccurrences(of: "\n", with: "")
        
        if stringToken == passwordToken {
            listeningUsers.append(client)
            send(client: client, message: "READY\n")
            let clientStatus = client.connect(timeout: 1)
            print("STATS \(clientStatus)")
        }else {
            //Auth failed, tell em.
            send(client: client, message: "FAIL\n")
            client.close()
        }
    }
    
    
    
    /// Send a message (but let's make it discardable because no I don't want a thousand warnings. File an issue with SwiftSocket if you don't like this.
    /// using extensions is too hardcore for just one method
    ///
    /// - Parameters:
    ///   - client: The client to send the message to
    ///   - message: The string to send to the client. We deal with nothing but strings in MessageProxy (at least for now and the forseeable future
    /// - Returns: Some sort of result? Don't bother with it really
    @discardableResult
    func send(client:TCPClient,message:String) -> Result {
        do {
            //Ignore the no throw warning here. This can throw SIGPIPE if the client disconnects
        return try client.send(string: message)
        }catch {
            return .failure(error)
        }
    }
    
    func broadcastToAllClients(jsonString:String) {
        for client in listeningUsers {
            switch send(client: client, message: jsonString) {
            case Result.success:
                print("sent ok!")
            case .failure(let error):
                print("send error \(error)")
            }
        }
    }
    
    
    
}
