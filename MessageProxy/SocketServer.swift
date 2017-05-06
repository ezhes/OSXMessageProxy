//
//  SocketServer.swift
//  MessageProxy
//
//  Created by Salman Husain on 5/5/17.
//  Copyright © 2017 Salman Husain. All rights reserved.
//

import Foundation
import Socket
import Dispatch


/*
 
 SOCKET SERVER API DOCUMENTATION::::
 I've never written a socket API before so I send my condolences

 You can test the API by connecting just using raw netcat
 
 Connection flow:
 1. User connects. The application sends the user socket to addNewSocket()
 2. The server sends an 'ACK' letting the client know it is ready for a login password
 3. The client has exactly two seconds to response with their password and a new line.
 4. If the login passes, the server responds with 'READY' but if the password auth fails then the server responds with 'FAIL'
 
 */


/// A socket server to provide live updates on messaging, sort of.
class SocketServer : NSObject {
    var API_TOKEN:String?
    
    let SOCKET_SERVER_PORT = 8736 //The port to run the socket server at
    
    static let bufferSize = 4096
    var listenSocket: Socket? = nil
    var continueRunning = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "com.CarbonDev.MessageProxy.SocketThread")
    
    deinit {
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
            print("[socket] deint socket")
        }
        self.listenSocket?.close()
    }
    
    
    /// Create a socket server and start it with a specific password
    ///
    /// - Parameter passwordProtectionToken: The password
    init(passwordProtectionToken:String) {
        super.init()
        
        API_TOKEN = passwordProtectionToken
        setupServer()
    }
    
    
    /// Build the server
    func setupServer() {
        DispatchQueue.global(qos: .background).async {
            [unowned self] in
            
            do {
                // Create an IPV6 socket...
                try self.listenSocket = Socket.create(family: .inet)
                
                guard let socket = self.listenSocket else {
                    
                    print("[socket] Unable to unwrap socket...")
                    return
                }
                
                try socket.listen(on: self.SOCKET_SERVER_PORT)
                
                print("[socket] Listening on port: \(socket.listeningPort)")
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()
                    
                    print("[socket] Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")                    
                    self.addNewConnection(socket: newSocket)
                    
                } while self.continueRunning
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("[socket] Unexpected error...")
                    return
                }
                
                if self.continueRunning {
                    
                    print("[socket] Error reported:\n \(socketError.description)")
                    
                }
            }
        }
    }
    
    
    /// Handle a new connection. Here is where we do authentication on the socket
    ///
    /// - Parameter socket: The socket
    func addNewConnection(socket: Socket) {
        
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .default)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in
            var readData = Data(capacity: SocketServer.bufferSize)
            do {
                //Prepare socket
                try socket.setReadTimeout(value: 2000)
                try socket.setWriteTimeout(value: 2000)
                // Write the welcome string...
                try socket.write(from: "ACK\n")
                _ = try socket.read(into: &readData)
                if String(data: readData, encoding: .utf8)?.replacingOccurrences(of: "\n", with: "") == self.API_TOKEN {
                    try socket.write(from: "READY\n")
                    // Add the new socket to the list of connected sockets since they are ready
                    self.socketLockQueue.sync { [unowned self, socket] in
                        self.connectedSockets[socket.socketfd] = socket
                    }
                }else {
                    try socket.write(from: "FAIL\n")
                    socket.close()
                }
                
                print("[socket] Socket: \(socket.remoteHostname):\(socket.remotePort) closed...")
                
                
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("[socket] Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("[socket] Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }
    
    
    /// Send a message to all the clients. It needs to be in the following format
    /// {"type" : "some message type", "content" : YOUR JSON OBJECT}
    ///
    /// - Parameter jsonMessage: The json message in the specified format
    func sendSocketBroadcast(jsonMessage:String) {
        //Kill the new lines. If they're doing JSON it shouldn't matter. Safety first. We only want one new line and that's at the end because we are using .readLine in the client
        let jsonMessage = jsonMessage.replacingOccurrences(of: "\n", with: "") + "\n"
        //Get lock so we don't run over eachother with multiple socket messages
        self.socketLockQueue.sync { [unowned self] in
            for socket in self.connectedSockets.values {
                do {
                    //Log since we aren't heartbeat
                    if !jsonMessage.contains("TCPALIVE") {
                        print("[socket] -->Sending \(jsonMessage) to socket at \(socket.remoteHostname):\(socket.remotePort)")
                    }
                    try socket.write(from: jsonMessage)
                }catch let error {
                    print("[socket] Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(error) ---> Disconnecting!")
                    //We failed to send them a message, deauth
                    self.connectedSockets.removeValue(forKey: socket.socketfd)
                }
            }
        }
        
    }
}
