//
//  ViewController.swift
//  MessageProxy
//
//  Created by Salman Husain on 3/1/17.
//  Copyright © 2017 Salman Husain. All rights reserved.
//

import Cocoa
import GRDB
import GCDWebServer



class ViewController: NSViewController {
    
    @IBOutlet var logView: NSTextView!
    
    var passwordToken = "" //the constant, unencrypted password. Doesn't save us from replay, just endpoint leackage
    var IFTTTMakeKey = "" //The IFTTT make key to use so we can easily send notifications anywhere
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        if let path = Bundle.main.path(forResource: "CONFIG", ofType: "plist") {
            let plistData = NSDictionary(contentsOfFile: path)
            //Stuff our password, crash if it's wrong. It's on you now
            passwordToken = plistData?.object(forKey: "protection_token") as! String
            IFTTTMakeKey = plistData?.object(forKey: "ifttt_maker_key") as! String
            //We've loaded the needed data, let's go
            setupWebserver()
        }else {
            //They didn't configure correctly
            let alert = NSAlert.init()
            alert.messageText = "MISSING CONFIGURATION IN BUILD PATH"
            alert.informativeText = "MessageProxy was built without a CONFIG.plist. Please rebuild the server application after duplicating CONFIG_EXAMPLE (rename it to CONFIG.plist) and fill in all the values!"
            alert.addButton(withTitle: "Terminate")
            alert.runModal()
        }
    }
    
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    func setupWebserver() {
        do {
            let messagesDatabaseLocation = (NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath as String) //Automatically expand our path so we don't have to find the users home directory
            let connector = try DatabaseConstructor(datebaseLocation: messagesDatabaseLocation,iftttMakerToken: IFTTTMakeKey);
            
            //Set log level warning to stop console spam
            GCDWebServer.setLogLevel(3)
            
            //Create our server
            let apiServer = GCDWebServer()
            apiServer?.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self, processBlock: {request in
                return GCDWebServerDataResponse(html:"") //Don't respond. Nothing is really hard to work off of. Security through obscurity???
                
            })
            
            apiServer?.addHandler(forMethod: "GET", path: "/isUp", request: GCDWebServerRequest.self, processBlock: {
                request in
                weak var weakSelf = self
                weakSelf?.uiPrint("Client checked in")
                return GCDWebServerDataResponse(html:"Invalid paramaters<br>\(String(describing: request?.query))")
            })
            
            apiServer?.addHandler(forMethod: "GET", path: "/conversations", request: GCDWebServerRequest.self, processBlock: {
                request in
                weak var weakConnector = connector;
                weak var weakSelf = self
                let passwordTokenFromRequest = request?.query["t"] as? String
                if (self.passwordToken == passwordTokenFromRequest) {
                    weakSelf?.uiPrint("\(request!.remoteAddressString!) request conversations")
                    let response = GCDWebServerDataResponse(html:weakConnector?.getJSONConversations())!
                    response.isGZipContentEncodingEnabled = true
                    return response
                }else {
                    let response = GCDWebServerDataResponse(html:"{\"error\" : \"\(passwordTokenFromRequest ?? "no token")\"}")!
                    response.statusCode = 401
                    response.isGZipContentEncodingEnabled = true
                    return response
                }
            })
            
            apiServer?.addHandler(forMethod: "GET", path: "/attachment", request: GCDWebServerRequest.self, processBlock: {
                request in
                weak var weakConnector = connector;
                weak var weakSelf = self
                let attachmentIDString = request?.query["id"] as? String
                let passwordTokenFromRequest = request?.query["t"] as? String
                if (self.passwordToken == passwordTokenFromRequest) {
                    if (attachmentIDString != nil) {
                        let attachment = weakConnector?.getAttachmentInfo(forAttachmentID: Int(attachmentIDString!)!)
                        //Check that we have an attachment
                        if (attachment?.pathToFile == nil) {
                            return GCDWebServerDataResponse(html:"Couldn't find attachment<br>\(String(describing: request?.query))")
                        }
                        let filePath = (attachment!.pathToFile! as NSString).expandingTildeInPath.replacingOccurrences(of: " ", with: "%20")
                        weakSelf?.uiPrint("\(request!.remoteAddressString!) -> serving attachment file://\(filePath)")
                        let fileURL = URL(string: "file://\(filePath)")!//URL(string: "file://" + (attachment!.pathToFile! as NSString).expandingTildeInPath)!
                        let data = NSData(contentsOf: fileURL) as Data!
                        //We do, build our response
                        let response = GCDWebServerDataResponse(data: data, contentType: attachment!.mimeType)!
                        response.isGZipContentEncodingEnabled = true
                        print("--> sending attachment")
                        return response
                    }else {
                        return GCDWebServerDataResponse(html:"Invalid paramaters<br>\(String(describing: request?.query))")
                    }
                }else {
                    let response = GCDWebServerDataResponse(html:"{\"error\" : \"\(passwordTokenFromRequest ?? "no token")\"}")!
                    response.statusCode = 401
                    response.isGZipContentEncodingEnabled = true
                    return response
                }
            })
            
            
            //Setup our send post.
            //Paramaters
            //Your post data needs the following values: participants and message. Each are strings. Participants is a comma seperate string of the recipients as you'd type them into the new message field in Message.app
            //curl http://127.0.0.1:8735/send  -XPOST -d "participants=imessage,3033744343&message=It's me from the command line"
            apiServer?.addHandler(forMethod: "POST", path: "/send", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {
                request in
                weak var weakConnector = connector;
                weak var weakSelf = self
                //Grab our post data parser as a form
                let formRequest = request as! GCDWebServerURLEncodedFormRequest
                if (formRequest.arguments != nil) {
                    let participiants = formRequest.arguments["participants"] as? String
                    let message = formRequest.arguments["message"] as? String
                    let passwordTokenFromRequest = formRequest.arguments["t"] as? String
                    //Do we have the correct paramaters? (are they set) and do we have the password?
                    if (participiants != nil && message != nil && self.passwordToken == passwordTokenFromRequest) {
                        //Yes! Ask our controller to send a message
                        weakSelf?.uiPrint("\(request!.remoteAddressString!) -> sending \(participiants!) :: \(message!) ")
                        weakConnector?.sendMessage(toRecipients: participiants!, withMessage: message!)
                        return GCDWebServerDataResponse(html:"OK: \(participiants!) :: \(message!)")
                    }
                    
                }
                //We couldn't find anyway else to return, give up
                return GCDWebServerDataResponse(html:"Invalid post data!")
            })
            
            //Setup our get messages post.
            //Paramaters
            //Your post data needs the following values: conversationID
            //curl http://127.0.0.1:8735/messages -XPOST -d "conversationID=37"
            apiServer?.addHandler(forMethod: "POST", path: "/messages", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {
                request in
                weak var weakConnector = connector;
                weak var weakSelf = self
                weakSelf?.uiPrint("\(request!.remoteAddressString!) request for messages")
                
                //Grab our post data parser as a form
                let formRequest = request as! GCDWebServerURLEncodedFormRequest
                if (formRequest.arguments != nil) {
                    let conversationID = formRequest.arguments["conversationID"] as? String
                    let passwordTokenFromRequest = formRequest.arguments["t"] as? String
                    //Do we have the correct paramaters? (are they set)
                    if (conversationID != nil && self.passwordToken == passwordTokenFromRequest) {
                        weakSelf?.uiPrint("\t-->Sending messages for ID \(conversationID!)")
                        //Yes! Get our data from the controller
                        let response = GCDWebServerDataResponse(html:weakConnector?.getJSONMessages(forChatID: Int(conversationID!)!))!
                        response.isGZipContentEncodingEnabled = true
                        return response
                    }
                    
                }
                //We couldn't find anyway else to return, give up
                return GCDWebServerDataResponse(html:"Invalid post data!")
            })
            
            apiServer?.start(withPort: 8735, bonjourName: "iMessage Proxy")
            if apiServer?.isRunning == true {
                uiPrint("Ready at \(apiServer!.serverURL!)")
            }else {
                uiPrint("Couldn't start the webserver! Failing permenantly")
            }
            
            
            
            
        } catch  {
            uiPrint("Database error!")
        }
        
        
    }
    public func uiPrint(_ content: Any) {
        print(content)
        
        //logView.append(string: "[\(Date())] \(content)\n")
    }
    
}

extension NSTextView {
    
    /// DO NOT USE
    /// THIS CRASHES ALL THE FUCKING TIME
    /// - Parameter string: <#string description#>
    func append(_ string: String) {
        //Update the text log on screen. We have to do this weird mutable editing because the nice way causes it to crash when you go too fast
        self.textStorage?.mutableString.append(string)
        self.scrollToEndOfDocument(nil)
    }
}


