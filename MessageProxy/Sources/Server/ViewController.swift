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
    
    @IBOutlet weak var serverStatusText: NSTextField!
    @IBOutlet weak var APIProtectionKeyTextField: NSTextField!
    @IBOutlet weak var makerAPIKeyTextField: NSTextField!
    @IBOutlet weak var versionText: NSTextField!
    
    var passwordToken = "" //the constant, unencrypted password. Doesn't save us from replay, just endpoint leackage
    var IFTTTMakeKey = "" //The IFTTT make key to use so we can easily send notifications anywhere
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            versionText.stringValue = "v\(version)"
        }
        let defaults = UserDefaults.standard
        //Setup SPARKLE updates
        defaults.set(true, forKey: "SUAutomaticallyUpdate")
        //Check if we've configured already
        if let apiProtectionKey = defaults.string(forKey: "protection_token") {
            APIProtectionKeyTextField.stringValue = apiProtectionKey
            passwordToken = apiProtectionKey
            //Optional to have the key so check null
            IFTTTMakeKey = defaults.string(forKey: "ifttt_maker_key") ?? "NO_MAKER_KEY_PROVIDED"
            makerAPIKeyTextField.stringValue = IFTTTMakeKey
            //We've loaded the needed data, let's go
            setupWebserver()
        }else {
            //They didn't configure correctly
            let alert = NSAlert.init()
            alert.messageText = "First run configuration"
            alert.informativeText = "MessageProxy can't find a saved API protection token and so it is neccesary that the application be configured.\n\nEnter some long random text for your API protection token. Don't use special charachters just A-z0-9. Really doesn't matter, just needs to be unique since this is not encryption but instead a cleartext password. DO NOT SHARE THIS TOKEN ONLINE ANYWHERE NEAR YOU API URL!!\n\nWhile optional, the IFTTT Maker token is really important because it's used to send notifications however you have configured previously according to README.md's instructions. GO HERE AND GET A TOKEN https://ifttt.com/maker_webhooks (you are to copy just the random text part of the given url once setup!!)\n\n\nEnter the required information, hit 'Write settings' and then quit and relaunch the application"
            alert.addButton(withTitle: "Continue")
            alert.runModal()
            
            
        }
    }
    
    @IBAction func saveConfiguration(_ sender: Any) {
        let defaults = UserDefaults.standard
        let newAPIKey = APIProtectionKeyTextField.stringValue
        if (newAPIKey != "") {
            defaults.set(newAPIKey, forKey: "protection_token")
            defaults.set(makerAPIKeyTextField.stringValue, forKey: "ifttt_maker_key")
            defaults.synchronize()
            let alert = NSAlert.init()
            
            passwordToken = newAPIKey;
            IFTTTMakeKey = makerAPIKeyTextField.stringValue;
            
            alert.messageText = "Saved"
            alert.informativeText = "The API protection key and IFTTT maker key have been updated sucesfully and the server, if running, will begin using them."
            alert.addButton(withTitle: "Dismiss")
            alert.runModal()
            print("Saved settings")
            
        }else {
           //an API key is required
            let alert = NSAlert.init()
            alert.messageText = "You need an API protection key"
            alert.informativeText = "While technically possible to run the server without any password, it's a horrible idea so I'm not going to let you do that. Enter a valid API protection key"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @IBAction func showGitHubReleases(_ sender: Any) {
        NSWorkspace.shared().open(URL(string: "https://github.com/shusain93/OSXMessageProxy/releases")!)

    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    func setupWebserver() {
        do {
            let messagesDatabaseLocation = (NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath as String) //Automatically expand our path so we don't have to find the users home directory
            let socketServer = SocketServer(apiToken: passwordToken)
            let connector = try DatabaseConstructor(datebaseLocation: messagesDatabaseLocation,iftttMakerToken: IFTTTMakeKey, liveMessageSocketServer: socketServer);
            
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
                
                let passwordTokenFromRequest = request?.query["t"] as? String
                if (self.passwordToken == passwordTokenFromRequest) {
                    //We have a valid token'd request. That means telling them the server version is safe. This is usefull for letting the client know if it can communicate properly
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    return GCDWebServerDataResponse(html:"{\"version\" : \(version)}")
                    }
                    
                }
                //Invalid/old probe. Give the old response which tells them we're here but not what we're at
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
                        //Check if we can serve the file
                        if (FileManager.default.fileExists(atPath: filePath)) {
                            //We do, build our response
                            let response = GCDWebServerFileResponse(file: filePath, isAttachment: false)
                            response?.isGZipContentEncodingEnabled = true
                            print("--> sending attachment")
                            return response
                        }else {
                            //No, send 404
                            let response = GCDWebServerDataResponse(html:"404 -- couldn't read file!")!
                            response.statusCode = 404
                            response.isGZipContentEncodingEnabled = true
                            return response
                        }
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
            //curl http://127.0.0.1:8735/send  -XPOST -d "participants=imessage,81328581&message=It's me from the command line"
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
                serverStatusText.stringValue = "Ready at \(apiServer!.serverURL!)"
            }else {
                serverStatusText.stringValue = "Couldn't start the server! Too low port? Already taken?"
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


