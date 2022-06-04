import Foundation
import GRDB
import Contacts

class FirebaseDatabaseConnector: NSObject {
    ///// DATABASE MANUAL CONFIGURATION
    private var DATABASE_PROBE_INTERVAL = 0.5 //How often should we check the database for new messages? Lower values mean better socket update speeds but uses more server processing power. Fast server? Use a lower probe value. 0.5 is about as fast as I've tried because it's plenty good
    
    
    
    
    private var databaseQueue:DatabaseQueue?; //Our database
    private var contactsDatabase:[String:String]? //our cached database of contacts
    private var messageQueue:[SendableMessage] = [] //Our queue of messages to send
    private var firebaseConnector:FirebaseConnector?
    
    /// Make an init with a special database. Should be used!
    ///
    /// - Parameter datebaseLocation: The path to the iMessage database
    init(datebaseLocation:String) throws {
        super.init()
        databaseQueue =  try DatabaseQueue(path: datebaseLocation)
        //Prepare our timer
        
        //Setup our lastFoundMessage
        let lastMessageROWIDRows = try databaseQueue?.inDatabase { db -> [Row]? in
            let rows = try Row.fetchAll(db, sql: "SELECT date from message ORDER BY date DESC LIMIT 1") //Get our last message and only its rowid
            return rows;
        }
        
        //Preapre contact
        contactsDatabase = getContactConverterDictionary()
        
        firebaseConnector = FirebaseConnector(callback: { (success, errorMessage) in
            self.firebaseConnector?.getLastMessageRowID(callback: { (success, error, lastMessage) in
                //just another startup
                //Do we have exactly the rows we wanted?
                if lastMessageROWIDRows?.count == 1 {
                    //Grab the only row's ROWID and store it as our last reference
                    self.lastMessageDate = lastMessage
                    //Now we are ready to fire our timer
                    _ = Timer.scheduledTimer(timeInterval:self.DATABASE_PROBE_INTERVAL, target: self, selector: #selector(self.checkForNewMessages), userInfo: nil, repeats: true);
                }else {
                    print("[ERROR!] COULD NOT GET A LAST ROWID. SELECT ROWID from message ORDER BY date DESC LIMIT 1 didn't return the correct ammount of rows.")
                }
            })
        })
        self.firebaseConnector?.startAuthentication()
    }
    
    
    /// Get a conversation table for handler_id to localized numbers
    ///
    /// - Returns: A swift dictionary
    func getHandlerConversationDictionary() -> [Int:String] {
        do {
            var handleDictionary:[Int:String] = [:]
            let rows = try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, sql: "SELECT * from handle")
                return rows;
            }
            
            rows?.forEach({
                handle in
                //Set our handle id as the key and our id as the value
                handleDictionary[handle["ROWID"]] = handle["id"]
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
                let rows = try Row.fetchAll(db, sql: "SELECT * from attachment where attachment.ROWID = \(forAttachmentID)")
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
            filledAttachment.id = attachmentData["ROWID"]
            filledAttachment.guid = attachmentData["guid"]
            filledAttachment.pathToFile = attachmentData["filename"]
            filledAttachment.mimeType = attachmentData["mime_type"]
            filledAttachment.fileName = attachmentData["transfer_name"]
            
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
                let rows = try Row.fetchAll(db, sql: "SELECT * from chat_message_join JOIN message ON message.ROWID = chat_message_join.message_id\n" +
                    "LEFT JOIN message_attachment_join on message_attachment_join.message_id = chat_message_join.message_id\n" + //Join our attachments IF we have it. Null if there are no attachments
                    "LEFT JOIN attachment on attachment.ROWID = message_attachment_join.attachment_id\n" + //Using the optional attachment, pull attachment locations
                    "where (chat_message_join.chat_id =\(forChatID))  ORDER BY date DESC LIMIT \(messageLimit)") //Specify order and limits + our chat ID
                return rows;
            }
            
        } catch  {
            return nil
        }
    }
    
    
    /// Convert an SQL message row into a dictionary
    ///
    /// - Parameters:
    ///   - message: The row
    ///   - handleTable: A reference to an internal table of handles to convert to human
    /// - Returns: A properly stuffed Swift accessable version
    func convertMessageToDictionary(message:Row,handleTable:[Int:String]) -> NSMutableDictionary {
        let messageDictionaryRepresentation = NSMutableDictionary()
        messageDictionaryRepresentation.setValue(message["message_id"], forKey: "message_id")
        messageDictionaryRepresentation.setValue(message[ "guid"], forKey: "guid")
        messageDictionaryRepresentation.setValue(message[ "ROWID"], forKey: "ROWID")
        messageDictionaryRepresentation.setValue(message[ "text"], forKey: "text")
        let contactName = handleTable[message[ "handle_id" ]]?.replacingOccurrences(of: "+1", with: "") //hackily fix intermittent country codes
        if (contactName != nil) {
            messageDictionaryRepresentation.setValue(contactsDatabase?[contactName!], forKey: "human_name")
            messageDictionaryRepresentation.setValue(contactName, forKey: "sender") //lookup our handle into a useful contact lookup name
        }
        messageDictionaryRepresentation.setValue(message[ "error"], forKey: "error")
        messageDictionaryRepresentation.setValue(message[ "date"], forKey: "date")
        messageDictionaryRepresentation.setValue(message[ "date_read"], forKey: "date_read")
        messageDictionaryRepresentation.setValue(message[ "date_delivered"], forKey: "date_delivered")
        messageDictionaryRepresentation.setValue(message[ "is_from_me"], forKey: "is_from_me")
        messageDictionaryRepresentation.setValue(message[ "chat_id"], forKey: "chat_id")
        messageDictionaryRepresentation.setValue(message[ "is_sent"], forKey: "is_sent")
        //Setup attachemnts
        let attachmentID = message[ "attachment_id" ]
        if (attachmentID != nil) {
            //We have an attachment!
            messageDictionaryRepresentation.setValue(true, forKey: "has_attachments")
            messageDictionaryRepresentation.setValue(attachmentID, forKey: "attachment_id")
            messageDictionaryRepresentation.setValue(message[ "uti"], forKey: "uti")
        }else {
            messageDictionaryRepresentation.setValue(false, forKey: "has_attachments")
        }
        
        return messageDictionaryRepresentation
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
            messageBundle.add(convertMessageToDictionary(message: message, handleTable: handleTable))
        })
        
        //Reverse our array since the datasource SQL gives us newest on top
        return messageBundle.reversed() as NSArray
    }
    
    
    /// Convert a message array to JSON
    ///
    /// - Parameter array: An array of dictionaries (which are messages)
    /// - Returns: A JSON string representing the data sent in
    func convertMessageArrayToJSON(array:NSArray) -> String {
        do {
            //Convert to Data
            let jsonData = try JSONSerialization.data(withJSONObject: array)
            
            //Convert back to string
            let JSONString = String(data: jsonData, encoding: String.Encoding.utf8)
            if (JSONString != nil) {
                
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
    
    /// Get a JSON representation of the messages for a chat
    ///
    /// - Parameters:
    ///   - forChatID: The chat to read from
    ///   - messageLimit: The last x messages to read
    /// - Returns: A string of JSON
    func getJSONMessages(forChatID:Int, messageLimit:Int = 100) ->String {
        let messageBundle = getMessages(forChatID: forChatID, messageLimit: messageLimit)
        return convertMessageArrayToJSON(array: messageBundle)
    }
    
    
    /// Get the raw conversation data from the databse
    ///
    /// - Returns: An array of SQL rows
    func getDatabaseConversations() -> [Row]? {
        do {
            return try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, sql: "SELECT * from chat_handle_join JOIN handle ON handle.ROWID = chat_handle_join.handle_id JOIN chat on chat.ROWID =  chat_handle_join.chat_id ")
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
            let key = "\(conversation[ "chat_id"] as! Int64)"
            
            //Do we have an old stored conversation?
            let oldConversation = conversationBundle.object(forKey: key) as? NSMutableDictionary
            if (oldConversation != nil) {
                //Yes, let's add the new participant
                let oldParticipants = oldConversation!.value(forKey: "IDs") as! String
                //Update our exsisting conversation's parts
                oldConversation!.setValue(oldParticipants + ", " + (conversation[ "id"] as! String).replacingOccurrences(of: "+1", with: ""), forKey: "IDs")
                //Check if we have a display name built by us
                if (oldConversation!.value(forKey: "has_manual_display_name") as? Bool == true) {
                    //Add the new person to the custom displayname
                    oldConversation!.setValue(oldConversation!.value(forKey: "display_name") as! String + ", " + getHumanName(handle_id: conversation[ "handle_id"]), forKey: "display_name")
                }
                //Update
                conversationBundle.setValue(oldConversation!, forKey: "\(key)")
            }else {
                //Don't have one yet!
                let conversationDictionaryRepresentation = NSMutableDictionary()
                conversationDictionaryRepresentation.setValue(conversation[ "chat_id"], forKey: "chat_id")
                conversationDictionaryRepresentation.setValue(conversation[ "handle_id"], forKey: "handle_id")
                conversationDictionaryRepresentation.setValue(conversation[ "id"], forKey: "IDs")
                conversationDictionaryRepresentation.setValue(conversation[ "service"], forKey: "service")
                let displayName = conversation[ "display_name"]
                //Check if we have a display name to set
                if (displayName as? String != "") {
                    conversationDictionaryRepresentation.setValue(conversation[ "display_name"], forKey: "display_name")
                    conversationDictionaryRepresentation.setValue(false, forKey: "has_manual_display_name") //The display name is a real named iMessage group and so it must be used as the send to in the client
                }else {
                    //No, we don't so let's build the human one
                    conversationDictionaryRepresentation.setValue(getHumanName(handle_id: conversation[ "handle_id"]), forKey: "display_name")
                    conversationDictionaryRepresentation.setValue(true, forKey: "has_manual_display_name")
                }
                
                var messages:[Int] = []
                getMessages(forChatID: conversation["chat_id"], messageLimit: 25).forEach({
                    (message) in
                    if let messageDict = message as? NSDictionary {
                     messages.append(messageDict.object(forKey: "ROWID") as! Int)
                    }
                })
                conversationDictionaryRepresentation.setValue(messages, forKey: "messages")
                //now let's add the message references
                conversationBundle.setValue(conversationDictionaryRepresentation, forKey: "\(key)")
                
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
    ///   - participiantListIsCustom: If the participiant list is custom built by us (i.e. to make human readable) it is not a raw participiant list. This being false denotes that the chat has been named in the database, not by us
    ///   - withMessage: The message to send
    func sendMessage(toRecipients:String,withMessage:String,participiantListIsCustom:Bool) {
        
        //Create our queue-able message
        let newMessage = SendableMessage()
        newMessage.messageContents = withMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) //we need to trim trailing white space/new lines otherwise the comparator fails and we flood the with messages. The iMessage client filters it out when we send it in so we HAVE to do this
        newMessage.recipients = toRecipients;
        
        //Determine our send alogrithim. If we have not generated a name post processing or there are multiple names (CSV) then we need to use UI automation
        let shouldUseUIAutomation = toRecipients.contains(", ") || participiantListIsCustom == false //if it's false that means there was already a name and we didn't modify it
        //..and send it. This is the user friendly way and we need to make a packet to send it
        sendMessage(message: newMessage, usingUIAutomation:shouldUseUIAutomation)
        
    }
    
    
    /// Send a message object safely. This is safe to use for resending messages
    ///
    /// - Parameter usingUIAutomation: If UI automation should be used to send the message. UI automation MUST be used if the message is a group chat.
    /// - Parameter message: The SendableMessage to send
    func sendMessage(message:SendableMessage, usingUIAutomation:Bool) {
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
            task.arguments = [Bundle.main.path(forResource: "messageSender", ofType: "scpt")!,self.messageQueue[0].messageContents!,self.messageQueue[0].recipients!, usingUIAutomation.description]
            task.launch()
            //Wait a bit before we check that it's been sent so that our message bundle is most accurate
            sleep(1)
            var messageHasBeenSent = false
            var messageRowIfSent:Row?
            //We'll check 5 times that our message has sent
            for _ in 0...12 {
                do {
                    let _ = try self.databaseQueue?.inDatabase { db -> [Row]? in
                        let rows = try Row.fetchAll(db, sql: "SELECT * from chat_message_join JOIN message ON message.ROWID = chat_message_join.message_id LEFT JOIN message_attachment_join on message_attachment_join.message_id = chat_message_join.message_id LEFT JOIN attachment on attachment.ROWID = message_attachment_join.attachment_id where (message.is_from_me == 1 AND message.error == 0 AND message.service == \"iMessage\")  ORDER BY date DESC LIMIT 15") //Get the last 15 messages WE sent. We're also pulling a huge amount of data here because if we did send we want to have a full valid message context
                        rows.forEach({
                            message in
                            //Check if we're in our sent messages
                            if (message[ "text"] == self.messageQueue[0].messageContents!) {
                                //Yes, flag as done
                                messageHasBeenSent = true
                                messageRowIfSent = message
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
                //Let the socket users know that some message with the following text was sent???
                let swiftyMessage = self.convertMessageToDictionary(message: messageRowIfSent!, handleTable: [:])
                //self.socketServer?.sendSocketBroadcast(jsonMessage: "{\"type\" : \"messageSent\", \"content\": \(self.convertMessageArrayToJSON(array: [swiftyMessage]))}")
                self.messageQueue.remove(at: 0)
                print(self.messageQueue)
                print("[Message Send] Our message has been sent, dequeing")
                
            }else {
                //Message failed to send after 13 seconds.
                self.messageQueue[0].sendFailures+=1;
                if (self.messageQueue[0].sendFailures >= 3) {
                    //We've failed too many times, notify that the message didn't send
                    DispatchQueue.main.async {
                        //self.sendNotification(title: "Failed to send message", contents: self.messageQueue[0].messageContents!, appURL: self.messageQueue[0].recipients!)
                    }
                    let jsonSafeMessageString = self.messageQueue[0].messageContents?.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
                    //self.socketServer?.sendSocketBroadcast(jsonMessage: "{\"type\" : \"messageSendFailure\", \"content\": \"\(jsonSafeMessageString ?? "")\"}")
                    
                    print("[Message Send] Permentally failed to send message. Notifying. Dequeded message")
                    self.messageQueue.remove(at: 0)
                    print(self.messageQueue)
                }else {
                    print("[Message Send] Message send failed. Trying \(self.messageQueue[0].sendFailures)/3")
                    self.messageQueue.remove(at: 0) //we need to remove here since when we recall we actually add another in the queue so ???
                    //Recursively retry. We have to call this one instead because if we re create we lose .sendFailures
                    self.sendMessage(message: message, usingUIAutomation: usingUIAutomation)
                }
            }
        }
    }
    
    
    
    
    //Holds a reference to the last rowid of the message we've seen. Used to know when we have to notify about new messages.
    var lastMessageDate = 0;
    
    /// Called by a global timer which checks if we have any new messages
    @objc func checkForNewMessages() {
        do {
            let messageNewMessageRows = try databaseQueue?.inDatabase { db -> [Row]? in
                let rows = try Row.fetchAll(db, sql: "SELECT * from chat_message_join JOIN message ON message.ROWID = chat_message_join.message_id WHERE date > \(lastMessageDate) ORDER BY date DESC LIMIT 100") //select all our messages since our last notification round
                return rows;
            }
            
            //Do we have any updates? We don't want to enumerate if we have nothing
            if messageNewMessageRows != nil && messageNewMessageRows!.count > 0 {
                print("Got \(messageNewMessageRows!.count) new messagess. Current last is \(lastMessageDate)")
                //Cache a lookup handle table because we need it now
                let handleTable = getHandlerConversationDictionary()
                firebaseConnector?.updateConversations(conversation: getConversations())
                //Now let's parse our messages
                messageNewMessageRows?.forEach({
                    newMessage in
                    //Mark all as sent pre-emptively incase we throw
                    lastMessageDate = newMessage["date"]
                    //Store our message handle id because we use it often
                    let handleID = newMessage["handle_id"] as? Int64
                    let swiftyMessage = convertMessageToDictionary(message: newMessage, handleTable: handleTable)
                    firebaseConnector?.addMessage(message: swiftyMessage, id: newMessage["ROWID"],date:newMessage["date"])
                    //Make sure we didn't send our message. Notifying about a SENT message is stupid
                    if (newMessage[ "is_from_me"] == 0) {
                        print("Sending...")
                        let senderName = getHumanName(handle_id: Int(handleID!))
                        //Build our notification sender
                        let appURL = handleTable[Int(handleID!)]?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? "Name Failure"
                        let message = newMessage[ "text"] as? String ?? "Unsupported message content"
                        //self.sendNotification(title: senderName, contents: message, appURL: appURL)
                        
                    }
                })
                
                //Send our updated conversation table LAST to not jam the socket
               // socketServer?.sendSocketBroadcast(jsonMessage: "{\"type\" : \"conversations\", \"content\" :\(getJSONConversations())}")
            }
            
            //update to NOW
            self.lastMessageDate = Int(NSDate().timeIntervalSinceReferenceDate);
            
            
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
