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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
		setupWebserver()

    }


    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
	
	func setupWebserver() {
		do {
			let connector = try DatabaseConstructor(datebaseLocation: "/Users/Salman/Library/Messages/chat.db");
			
            //Set log level warning to stop console spam
            GCDWebServer.setLogLevel(3)
            
            //Create our server
			let apiServer = GCDWebServer()
            apiServer?.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self, processBlock: {request in
				return GCDWebServerDataResponse(html:"Access Denied")
				
			})
			
			apiServer?.addHandler(forMethod: "GET", path: "/conversations", request: GCDWebServerRequest.self, processBlock: {
				request in
				weak var weakConnector = connector;
				let response = GCDWebServerDataResponse(html:weakConnector?.getJSONConversations())!
                response.isGZipContentEncodingEnabled = true
				return response
			})
			
            apiServer?.addHandler(forMethod: "GET", path: "/attachment", request: GCDWebServerRequest.self, processBlock: {
                request in
                weak var weakConnector = connector;
                let attachmentIDString = request?.query["id"] as? String
                
                if (attachmentIDString != nil) {
                    let attachment = weakConnector?.getAttachmentInfo(forAttachmentID: Int(attachmentIDString!)!)
                    //Check that we have an attachment
                    if (attachment?.pathToFile == nil) {
                        return GCDWebServerDataResponse(html:"Couldn't find attachment<br>\(request?.query)")
                    }
                    let filePath = (attachment!.pathToFile! as NSString).expandingTildeInPath.replacingOccurrences(of: " ", with: "%20")
                    print("file://\(filePath)")
                    let fileURL = URL(string: "file://\(filePath)")!//URL(string: "file://" + (attachment!.pathToFile! as NSString).expandingTildeInPath)!
                    let data = NSData(contentsOf: fileURL) as Data!
                    //We do, build our response
                    let response = GCDWebServerDataResponse(data: data, contentType: attachment!.mimeType)!
                    response.isGZipContentEncodingEnabled = true
                    return response
                }else {
                    return GCDWebServerDataResponse(html:"Invalid paramaters<br>\(request?.query)")
                }
            })
            
            
			//Setup our send post.
			//Paramaters
			//Your post data needs the following values: participants and message. Each are strings. Participants is a comma seperate string of the recipients as you'd type them into the new message field in Message.app
			//curl http://127.0.0.1:8735/send  -XPOST -d "participants=imessage,3033744343&message=It's me from the command line"
			apiServer?.addHandler(forMethod: "POST", path: "/send", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {
				request in
				weak var weakConnector = connector;
                
                //Grab our post data parser as a form
				let formRequest = request as! GCDWebServerURLEncodedFormRequest
				if (formRequest.arguments != nil) {
					let participiants = formRequest.arguments["participants"] as? String
					let message = formRequest.arguments["message"] as? String
                    //Do we have the correct paramaters? (are they set)
                    if (participiants != nil && message != nil) {
                        //Yes! Ask our controller to send a message
                        print("Sending \(participiants!) :: \(message!) ")
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
                
                //Grab our post data parser as a form
                let formRequest = request as! GCDWebServerURLEncodedFormRequest
                if (formRequest.arguments != nil) {
                    let conversationID = formRequest.arguments["conversationID"] as? String
                    //Do we have the correct paramaters? (are they set)
                    if (conversationID != nil) {
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
                print("Ready at \(apiServer!.serverURL!)")
            }else {
                print("Couldn't start the webserver! Failing permenantly")
            }
            
            
			
			
		} catch  {
			print("Database error!")
		}
		
		
	}
    
    
}

