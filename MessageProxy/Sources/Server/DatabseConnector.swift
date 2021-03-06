//
//  DatabseConnector.swift
//  MessageProxy
//
//  Created by Allison Husain on 3/1/17.
//  Copyright © 2017 Allison Husain. All rights reserved.
//

import Foundation
import GRDB
import Contacts

class DatabaseConstructor: NSObject {
    private var databaseQueue:DatabaseQueue?; //Our database
    private var contactsDatabase:[String:String]? //our cached database of contacts
    private var messageQueue:[SendableMessage] = [] //Our queue of messages to send
    private var socketServer:SocketServer? //Our socket server for live messaging
    
    private var IFTTT_token:String = ""
    /// Make an init with a special database. Should be used!
    ///
    /// - Parameter datebaseLocation: The path to the iMessage database
    init(datebaseLocation:String, iftttMakerToken:String, liveMessageSocketServer:SocketServer) throws {
        super.init()
        //store our notifier token
        IFTTT_token = iftttMakerToken
        databaseQueue =  try DatabaseQueue(path: datebaseLocation)
        socketServer = liveMessageSocketServer
        
        //Prepare our timer
        //Setup our lastFoundMessage
        let lastMessageROWIDRows = try databaseQueue?.inDatabase { db -> [Row]? in
            let rows = try Row.fetchAll(db, "SELECT date from message ORDER BY date DESC LIMIT 1") //Get our last message and only its rowid
            return rows;
        }
        //Do we have exactly the rows we wanted?
        if lastMessageROWIDRows?.count == 1 {
            //Grab the only row's ROWID and store it as our last reference
            lastMessageDate = lastMessageROWIDRows![0].value(named: "date")
            //Now we are ready to fire our timer
            _ = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(self.checkForNewMessages), userInfo: nil, repeats: true);
        }else {
            print("[ERROR!] COULD NOT GET A LAST ROWID. SELECT ROWID from message ORDER BY date DESC LIMIT 1 didn't return the correct ammount of rows.")
        }
        //Preapre contact
        contactsDatabase = getContactConverterDictionary()
    }
    
    
    /// Get a conversation table for handler_id to localized numbers
    ///
    /// - Returns: A swift dictionary
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
    
    
    /// Get a conversion table for numbers/emails into human contact names from the server
    ///
    /// - Returns: A swift dictionary. Key is the email/number and value is the name`
    func getContactConverterDictionary() -> [String:String] {
        var contactLookUpDataSource:[String:String] = [:] //create our data store
        let adderssBook = CNContactStore()
        let contactRequest = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor,CNContactPhoneNumbersKey as CNKeyDescriptor,CNContactFamilyNameKey as CNKeyDescriptor,CNContactGivenNameKey as CNKeyDescriptor])
        do {
            try adderssBook.enumerateContacts(with: contactRequest, usingBlock: {
                (contact, stop) -> Void in
                //Parse phones
                contact.phoneNumbers.forEach({
                    phoneNumber in
                    contactLookUpDataSource[(phoneNumber.value.value(forKey: "digits") as! String).replacingOccurrences(of: "+1", with: "")] = "\(contact.givenName) \(contact.familyName)" //Very hackily fix country code. It only works for the US but since I live there we can lower out standard. Should use google's libphonenumber
                })
                
                //Parse emails
                contact.emailAddresses.forEach({
                    email in
                    contactLookUpDataSource[email.value as String] = "\(contact.givenName) \(contact.familyName)"
                })
            })
            //We're done, give up table back
            return contactLookUpDataSource
        }catch {
            print("[ERROR!] UNABLE TO READ CONTACTS")
            return [:]
        }
        
    }
    
    func getAttachmentInfo(forAttachmentID:Int) -> Attachment? {
        do {
            let attachmentRow =  try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, "SELECT * from attachment where attachment.ROWID = \(forAttachmentID)")
                return rows;
            }
            
            //Make sure what we got was expected before we try to parse
            if attachmentRow == nil || attachmentRow?.count != 1 {
                return nil
            }
            
            //Now start parsing.
            let attachmentData = attachmentRow![0]
            //Build our container..
            let filledAttachment = Attachment()
            filledAttachment.id = attachmentData.value(named: "ROWID")
            filledAttachment.guid = attachmentData.value(named: "guid")
            filledAttachment.pathToFile = attachmentData.value(named: "filename")
            filledAttachment.mimeType = attachmentData.value(named: "mime_type")
            filledAttachment.fileName = attachmentData.value(named: "transfer_name")
            
            return filledAttachment
        } catch  {
            return nil
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
                let rows = try Row.fetchAll(db, "SELECT * from chat_message_join JOIN message ON message.ROWID = chat_message_join.message_id\n" +
                    "LEFT JOIN message_attachment_join on message_attachment_join.message_id = chat_message_join.message_id\n" + //Join our attachments IF we have it. Null if there are no attachments
                    "LEFT JOIN attachment on attachment.ROWID = message_attachment_join.attachment_id\n" + //Using the optional attachment, pull attachment locations
                    "where (chat_message_join.chat_id =\(forChatID))  ORDER BY date DESC LIMIT \(messageLimit)") //Specify order and limits + our chat ID
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
            let contactName = handleTable[message.value(named: "handle_id")]?.replacingOccurrences(of: "+1", with: "") //hackily fix intermittent country codes
            if (contactName != nil) {
                messageDictionaryRepresentation.setValue(contactsDatabase?[contactName!], forKey: "human_name")
                messageDictionaryRepresentation.setValue(contactName, forKey: "sender") //lookup our handle into a useful contact lookup name
            }
            messageDictionaryRepresentation.setValue(message.value(named: "error"), forKey: "error")
            messageDictionaryRepresentation.setValue(message.value(named: "date"), forKey: "date")
            messageDictionaryRepresentation.setValue(message.value(named: "date_read"), forKey: "date_read")
            messageDictionaryRepresentation.setValue(message.value(named: "date_delivered"), forKey: "date_delivered")
            messageDictionaryRepresentation.setValue(message.value(named: "is_from_me"), forKey: "is_from_me")
            
            //Setup attachemnts
            let attachmentID = message.value(named: "attachment_id")
            if (attachmentID != nil) {
                //We have an attachment!
                messageDictionaryRepresentation.setValue(true, forKey: "has_attachments")
                messageDictionaryRepresentation.setValue(attachmentID, forKey: "attachment_id")
                messageDictionaryRepresentation.setValue(message.value(named: "uti"), forKey: "uti")
            }else {
                messageDictionaryRepresentation.setValue(false, forKey: "has_attachments")
            }
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
                print(JSONString!)
                //Remove the object replacement characters from our string. These come from attachments
                return JSONString!.replacingOccurrences(of: "\u{FFFC}", with: "")
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
                let rows = try Row.fetchAll(db, "SELECT * from chat_handle_join JOIN handle ON handle.ROWID = chat_handle_join.handle_id JOIN chat on chat.ROWID =  chat_handle_join.chat_id ")
                return rows;
            }
        } catch  {
            return []
        }
    }
    
    
    /// Get a formatted dictionary of the conversations with relevant metadata and the last message in each
    ///
    /// - Returns: Dictionary of dictionaries
    func getConversations() -> NSArray {
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
                oldConversation!.setValue(oldParticipants + ", " + (conversation.value(named: "id") as! String).replacingOccurrences(of: "+1", with: ""), forKey: "IDs")
                //Check if we have a display name built by us
                if (oldConversation!.value(forKey: "has_manual_display_name") as? Bool == true) {
                    //Add the new person to the custom displayname
                    oldConversation!.setValue(oldConversation!.value(forKey: "display_name") as! String + ", " + getHumanName(handle_id: conversation.value(named: "handle_id")), forKey: "display_name")
                }
                //Update
                conversationBundle.setValue(oldConversation!, forKey: "\(key)")
            }else {
                //Don't have one yet!
                let conversationDictionaryRepresentation = NSMutableDictionary()
                conversationDictionaryRepresentation.setValue(conversation.value(named: "chat_id"), forKey: "chat_id")
                conversationDictionaryRepresentation.setValue(conversation.value(named: "handle_id"), forKey: "handle_id")
                conversationDictionaryRepresentation.setValue(conversation.value(named: "id"), forKey: "IDs")
                conversationDictionaryRepresentation.setValue(conversation.value(named: "service"), forKey: "service")
                let displayName = conversation.value(named: "display_name")
                //Check if we have a display name to set
                if (displayName as? String != "") {
                    conversationDictionaryRepresentation.setValue(conversation.value(named: "display_name"), forKey: "display_name")
                    conversationDictionaryRepresentation.setValue(false, forKey: "has_manual_display_name") //The display name is a real named iMessage group and so it must be used as the send to in the client
                }else {
                    //No, we don't so let's build the human one
                    conversationDictionaryRepresentation.setValue(getHumanName(handle_id: conversation.value(named: "handle_id")), forKey: "display_name")
                    conversationDictionaryRepresentation.setValue(true, forKey: "has_manual_display_name")
                }
                
                //Add our last message. This gives us a blurb, last date, etc
                if let mostRecentBlurbMessage = getMessages(forChatID: conversation.value(named: "chat_id"), messageLimit: 1).firstObject {
                    conversationDictionaryRepresentation.setValue(mostRecentBlurbMessage, forKey: "lastMessage")
                    //Only add if we've added our last message sucessfully
                    conversationBundle.setValue(conversationDictionaryRepresentation, forKey: "\(key)")
                }
                
            }
            
        })
        
        return conversationBundle.allValues as NSArray
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
                print(JSONString!)
                //Remove the object replacement characters from our string. These come from attachments
                return JSONString!.replacingOccurrences(of: "\u{FFFC}", with: "")
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
        //Create our queue-able message
        let newMessage = SendableMessage()
        newMessage.messageContents = withMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) //we need to trim trailing white space/new lines otherwise the comparator fails and we flood the with messages. The iMessage client filters it out when we send it in so we HAVE to do this
        newMessage.recipients = toRecipients;
        //..and send it. This is the user friendly way and we need to make a packet to send it
        sendMessage(message: newMessage)
        
    }
    
    
    /// Send a message object safely. This is safe to use for resending messages
    ///
    /// - Parameter message: The SendableMessage to send
    func sendMessage(message:SendableMessage) {
        messageQueue.append(message)
        DispatchQueue.global().async {
            [unowned self ] in
            //Really shitty way to do this. I don't want to learn how to do block queueing and so we're just going to make threads for each message. fuck em if they send too fast.
            //We are waiting until the first queue object is equal to our goal
            while (self.messageQueue.first?.messageContents != message.messageContents) {
                Thread.sleep(forTimeInterval: 1)
            }
            print("[Message Send] Message \(self.messageQueue[0].messageContents!) has reached the front of the queue")
            //We're last in queue. We should also be safe in terms of thread safety
            //Send our message
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            //Set up the arguments!
            task.arguments = [Bundle.main.path(forResource: "messageSender", ofType: "scpt")!,self.messageQueue[0].messageContents!,self.messageQueue[0].recipients!]
            task.launch()
            //Wait a bit before we check that it's been sent
            var messageHasBeenSent = false
            //We'll check 5 times that our message has sent
            for _ in 0...12 {
                do {
                    let _ = try self.databaseQueue?.inDatabase { db -> [Row]? in
                        let rows = try Row.fetchAll(db, "SELECT message.text from message where message.is_from_me == 1 AND message.error == 0 AND message.service == \"iMessage\" ORDER BY date DESC LIMIT 15") //Get the last 15 messages WE sent
                        rows.forEach({
                            message in
                            //Check if we're in our sent messages
                            if (message.value(named: "text") == self.messageQueue[0].messageContents!) {
                                //Yes, flag as done
                                messageHasBeenSent = true
                            }
                        })
                        return rows
                    }
                    
                } catch  {
                    print("!!!! -> FAILED TO CHCK FOR MESSAGES")
                }
                //Break early if we've sent
                if (messageHasBeenSent) {
                    break
                }
                Thread.sleep(forTimeInterval: 1)
            }
            if (messageHasBeenSent) {
                //We've been sent.
                self.messageQueue.remove(at: 0)
                print(self.messageQueue)
                print("[Message Send] Our message has been sent, dequeing")
            }else {
                //Message failed to send after 13 seconds.
                self.messageQueue[0].sendFailures+=1;
                if (self.messageQueue[0].sendFailures >= 3) {
                    //We've failed too many times, notify that the message didn't send
                    DispatchQueue.main.async {
                        self.sendNotification(title: "Failed to send message", contents: self.messageQueue[0].messageContents!, appURL: self.messageQueue[0].recipients!)
                    }
                    print("[Message Send] Permentally failed to send message. Notifying. Dequeded message")
                    self.messageQueue.remove(at: 0)
                    print(self.messageQueue)
                }else {
                    print("[Message Send] Message send failed. Trying \(self.messageQueue[0].sendFailures)/3")
                    self.messageQueue.remove(at: 0) //we need to remove here since when we recall we actually add another in the queue so ???
                    //Recursively retry. We have to call this one instead because if we re create we lose .sendFailures
                    self.sendMessage(message: message)
                }
            }
        }
    }
    
    
    /// Send a push notification to the device
    ///
    /// - Parameters:
    ///   - title: The notification source
    ///   - contents: The message contents
    ///   - appURL: The call back url
    func sendNotification(title:String,contents:String,appURL:String) {
        do {
            let postDictionary = ["value1":title,"value2":contents,"value3":appURL]
            let postData = try JSONSerialization.data(withJSONObject: postDictionary, options: JSONSerialization.WritingOptions.prettyPrinted)
            //Now let's build our request
            let request = NSMutableURLRequest(url: URL(string: "https://maker.ifttt.com/trigger/imessageRecieved/with/key/\(IFTTT_token)")!)
            request.httpMethod = "POST"
            request.setValue("iMessageProxy/1.0/AllisonHusain", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = postData
            
            //Send our request
            let _ = NSURLConnection(request: request as URLRequest, delegate: nil)
            
        }catch let parseError {
            print(parseError)
        }
    }
    
    
    //Holds a reference to the last rowid of the message we've seen. Used to know when we have to notify about new messages.
    var lastMessageDate = 0;
    /// Called by a global timer which checks if we have any new messages
    func checkForNewMessages() {
        socketServer?.broadcastToAllClients(jsonString: "Server says hey")
        do {
            let messageNewMessageRows = try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, "SELECT * from message WHERE date > \(lastMessageDate) ORDER BY date LIMIT 25") //select all our messages since our last notification round
                return rows;
            }
            
            //Do we have any updates? We don't want to enumerate if we have nothing
            if messageNewMessageRows != nil && messageNewMessageRows!.count > 0 {
                print("Got \(messageNewMessageRows!.count) new messagess. Current last is \(lastMessageDate)")
                //Cache a lookup handle table because we need it now
                let handleTable = getHandlerConversationDictionary()
                
                //Now let's parse our messages
                messageNewMessageRows?.forEach({
                    newMessage in
                    //Mark all as sent pre-emptively incase we throw
                    lastMessageDate = newMessage.value(named: "date")
                    //Store our message handle id because we use it often
                    let handleID = newMessage.value(named: "handle_id") as? Int64
                    //Make sure we didn't send our message. Notifying about a SENT message is stupid
                    
                    if (newMessage.value(named: "is_from_me") == 0) {
                        print("Sending...")
                        
                        let senderName = getHumanName(handle_id: Int(handleID!))
                        //Build our notification sender
                        let appURL = handleTable[Int(handleID!)]?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? "Name Failure"
                        let message = newMessage.value(named: "text") as? String ?? "Unsupported message content"
                        self.sendNotification(title: senderName, contents: message, appURL: appURL)
                        
                    }
                })
            }
            
            
        } catch  {
            print("TIMER DATABASE READ ERROR")
        }
    }
    
    func getHumanName(handle_id:Int) -> String {
        let handleTable = getHandlerConversationDictionary()
        let contactName = handleTable[handle_id]?.replacingOccurrences(of: "+1", with: "") //hackily fix intermittent country
        var senderName:String?
        //Let's build our sender name
        if (contactName != nil) {
            let humanName = contactsDatabase?[contactName!]
            if (humanName != nil) {
                senderName = humanName
            }else {
                //Unkown number, send the number itself
                senderName = handleTable[handle_id]
            }
        }else {
            senderName = "Name failure: \(handle_id)"
        }
        return senderName!
    }
    
}


/// A wrapper for the SQL attachments from the table
class Attachment {
    var id:Int?
    var messageID:Int?
    var guid:String?
    var pathToFile:String?
    var mimeType:String?
    var fileName:String?
}

/// A wrapper for messages we are sending
class SendableMessage {
    var messageContents:String?
    var recipients:String?
    var sendFailures = 0
}
