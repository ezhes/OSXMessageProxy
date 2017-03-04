//
//  DatabseConnector.swift
//  MessageProxy
//
//  Created by Salman Husain on 3/1/17.
//  Copyright © 2017 Salman Husain. All rights reserved.
//

import Foundation
import GRDB

class DatabaseConstructor: NSObject {
    private var databaseQueue:DatabaseQueue?; //Our database
    
    
    /// Make an init with a special database. Should be used!
    ///
    /// - Parameter datebaseLocation: The path to the iMessage database
    init(datebaseLocation:String) throws {
        super.init()
        databaseQueue =  try DatabaseQueue(path: datebaseLocation)
        
        //Prepare our timer
        //Setup our lastFoundMessage
        let lastMessageROWIDRows = try databaseQueue?.inDatabase { db -> [Row]? in
            let rows = try Row.fetchAll(db, "SELECT ROWID from message ORDER BY date DESC LIMIT 1") //Get our last message and only its rowid
            return rows;
        }
        //Do we have exactly the rows we wanted?
        if lastMessageROWIDRows?.count == 1 {
            //Grab the only row's ROWID and store it as our last reference
            lastMessageROWID = lastMessageROWIDRows![0].value(named: "ROWID")
            //Now we are ready to fire our timer
            _ = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(self.checkForNewMessages), userInfo: nil, repeats: true);
        }else {
            print("[ERROR!] COULD NOT GET A LAST ROWID. SELECT ROWID from message ORDER BY date DESC LIMIT 1 didn't return the correct ammount of rows.")
        }
        
        

        
    }
	
    func getHandlerConversationDictionary() -> [Int:String] {
        do {
            var handleDictionary:[Int:String] = [:]
            let rows = try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, "SELECT * from handle")
                return rows;
            }
            
            rows?.forEach({
                handle in
                //Set our handle id as the key and our id as the value
                handleDictionary[handle.value(named: "ROWID")] = handle.value(named: "id")
            })
            //We're done, return!
            return handleDictionary
            
        } catch  {
            return [:]
        }
    }
    
    /// Read out messages from the database.
    ///
    /// - Parameters:
    ///   - forChatID: The chat to read for
    ///   - messageLimit: The last x messages to read
    /// - Returns: Array of SQL rows
    func getDatabseMessages(forChatID:Int, messageLimit:Int) -> [Row]? {
        do {
            return try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, "SELECT * from chat_message_join JOIN message ON message.ROWID = chat_message_join.message_id where chat_message_join.chat_id = \(forChatID) ORDER BY date DESC LIMIT \(messageLimit)")
                return rows;
            }
            
        } catch  {
            return nil
        }
    }
	
	/// Get a parsed array of messages
	///
	/// - Parameters:
	///   - forChatID: The chat to read from
	///   - messageLimit: The last x messages to read
	/// - Returns: An array of messages (as dictionaries!) with the relevant information stored in them
	func getMessages(forChatID:Int, messageLimit:Int = 100) -> NSArray {
        //Cache a lookup handle table
        let handleTable = getHandlerConversationDictionary()
		let messageBundle = NSMutableArray()
		let conversationMessages = getDatabseMessages(forChatID: forChatID,messageLimit: messageLimit)
		
		conversationMessages?.forEach({
			message in
			let messageDictionaryRepresentation = NSMutableDictionary()
			messageDictionaryRepresentation.setValue(message.value(named: "message_id"), forKey: "message_id")
			messageDictionaryRepresentation.setValue(message.value(named: "guid"), forKey: "guid")
			messageDictionaryRepresentation.setValue(message.value(named: "text"), forKey: "text")
			messageDictionaryRepresentation.setValue(message.value(named: "handle_id"), forKey: "handle_id")
            messageDictionaryRepresentation.setValue(handleTable[message.value(named: "handle_id")], forKey: "sender") //lookup our handle into a useful contact lookup name
			messageDictionaryRepresentation.setValue(message.value(named: "error"), forKey: "error")
			messageDictionaryRepresentation.setValue(message.value(named: "date"), forKey: "date")
			messageDictionaryRepresentation.setValue(message.value(named: "date_read"), forKey: "date_read")
			messageDictionaryRepresentation.setValue(message.value(named: "date_delivered"), forKey: "date_delivered")
			messageDictionaryRepresentation.setValue(message.value(named: "is_from_me"), forKey: "is_from_me")
			messageBundle.add(messageDictionaryRepresentation)
		})
		
        //Reverse our array since the datasource SQL gives us newest on top
		return messageBundle.reversed() as NSArray
	}
	
	
	/// Get a JSON representation of the messages for a chat
	///
	/// - Parameters:
	///   - forChatID: The chat to read from
	///   - messageLimit: The last x messages to read
	/// - Returns: A string of JSON
	func getJSONMessages(forChatID:Int, messageLimit:Int = 100) ->String {
		let messageBundle = getMessages(forChatID: forChatID, messageLimit: messageLimit)
		do {
			
			//Convert to Data
			let jsonData = try JSONSerialization.data(withJSONObject: messageBundle, options: JSONSerialization.WritingOptions.prettyPrinted)
			
			//Convert back to string
			let JSONString = String(data: jsonData, encoding: String.Encoding.utf8)
			if (JSONString != nil) {
				return JSONString!
			}else {
				//Failed to generate a JSON string
				return ""
			}
			
		} catch {
			//Failed to serialize?
			return ""
		}
	}
	
	
    /// Get the raw conversation data from the databse
    ///
    /// - Returns: An array of SQL rows
    func getDatabaseConversations() -> [Row]? {
        do {
            return try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, "SELECT * from chat_handle_join JOIN handle ON handle.ROWID = chat_handle_join.handle_id JOIN chat on chat.ROWID =  chat_handle_join.chat_id")
                return rows;
            }
        } catch  {
            return nil
        }
    }
	
	
	/// Get a formatted dictionary of the conversations with relevant metadata and the last message in each
	///
	/// - Returns: Dictionary of dictionaries
	func getConversations() -> NSDictionary {
		let conversationBundle = NSMutableDictionary()
		let conversationRows = getDatabaseConversations()
		
		conversationRows?.forEach({
			conversation in
			let key = "\(conversation.value(named: "chat_id") as! Int64)"
			
			//Do we have an old stored conversation?
			let oldConversation = conversationBundle.object(forKey: key) as? NSMutableDictionary
			if (oldConversation != nil) {
				//Yes, let's add the new participant
				let oldParticipants = oldConversation!.value(forKey: "IDs") as! String
				//Update our exsisting conversation's parts
				oldConversation!.setValue(oldParticipants + ", " + conversation.value(named: "id"), forKey: "IDs")
				//Update
				conversationBundle.setValue(oldConversation!, forKey: "\(key)")
			}else {
				//Don't have one yet!
				let conversationDictionaryRepresentation = NSMutableDictionary()
				conversationDictionaryRepresentation.setValue(conversation.value(named: "chat_id"), forKey: "chat_id")
				conversationDictionaryRepresentation.setValue(conversation.value(named: "handle_id"), forKey: "handle_id")
				conversationDictionaryRepresentation.setValue(conversation.value(named: "id"), forKey: "IDs")
				conversationDictionaryRepresentation.setValue(conversation.value(named: "service"), forKey: "service")
				conversationDictionaryRepresentation.setValue(conversation.value(named: "display_name"), forKey: "display_name")
				//Add our last message. This gives us a blurb, last date, etc
				conversationDictionaryRepresentation.setValue(getMessages(forChatID: conversation.value(named: "chat_id"), messageLimit: 1).firstObject, forKey: "lastMessage")
				conversationBundle.setValue(conversationDictionaryRepresentation, forKey: "\(key)")
			}
			
		})
		
		return conversationBundle
	}
	
	
	
    /// Get a JSON representation of the conversations
    ///
    /// - Returns: A JSON formatted version of the conversations (and their last message!)
    func getJSONConversations() ->String {
		//Grab out datasource so that we can convert it into JSON
		let conversationBundle = getConversations()
        do {
            
            //Convert to Data
            let jsonData = try JSONSerialization.data(withJSONObject: conversationBundle, options: JSONSerialization.WritingOptions.prettyPrinted)
            
            //Convert back to string
			let JSONString = String(data: jsonData, encoding: String.Encoding.utf8)
            if (JSONString != nil) {
                return JSONString!
			}else {
				//Failed to generate a JSON string
				return ""
			}
			
		} catch {
			//Failed to serialize?
			return ""
		}
    }
	
	
	/// Send a message using the Messages.app on the server machine
	///
	/// - Parameters:
	///   - toRecipients: A human or phone number list of comma seperated phone numbers/emails/group nam to send to
	///   - withMessage: The message to send
	func sendMessage(toRecipients:String,withMessage:String) {
		let task = Process()
		task.launchPath = "/usr/bin/osascript"
		//Set up the arguments!
		task.arguments = [Bundle.main.path(forResource: "messageSender", ofType: "scpt")!,withMessage,toRecipients]
		task.launch()
	}
    
    
    //Holds a reference to the last rowid of the message we've seen. Used to know when we have to notify about new messages.
    var lastMessageROWID = 0;
    /// Called by a global timer which checks if we have any new messages
    func checkForNewMessages() {
        do {
            let messageNewMessageRows = try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, "SELECT * from message WHERE ROWID > \(lastMessageROWID) ORDER BY date DESC LIMIT 25") //select all our messages since our last notification round
                return rows;
            }
            
            //Do we have any updates? We don't want to enumerate if we have nothing
            if messageNewMessageRows != nil && messageNewMessageRows!.count > 0 {
                print("Got \(messageNewMessageRows!.count) new messagess")
                //Cache a lookup handle table because we need it now
                let handleTable = getHandlerConversationDictionary()
            
                //Now let's parse our messages
                try messageNewMessageRows?.forEach({
                    newMessage in
                    //Mark all as sent pre-emptively incase we throw
                    lastMessageROWID = newMessage.value(named: "ROWID")
                    //Make sure we didn't send our message. Notifying about a SENT message is stupid
                    if (newMessage.value(named: "is_sent") == 0) {
                        //Build our notification sender
                        let postDictionary = ["value1":handleTable[newMessage.value(named: "handle_id")],"value2":newMessage.value(named: "text")]
                        let postData = try JSONSerialization.data(withJSONObject: postDictionary, options: JSONSerialization.WritingOptions.prettyPrinted)
                        //Now let's build our request
                        let request = NSMutableURLRequest(url: URL(string: "https://maker.ifttt.com/trigger/imessageRecieved/with/key/3HEnQUJ1WuSZcOAKYW9XJ")!)
                        request.httpMethod = "POST"
                        request.setValue("iMessageProxy/1.0/SalmanHusain", forHTTPHeaderField: "User-Agent")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = postData
                        //Send our request
                        let _ = NSURLConnection(request: request as URLRequest, delegate: nil)
                        
                    }
                })
            }
            
            
        } catch  {
            print("TIMER DATABASE READ ERROR")
        }
    }
    
}
