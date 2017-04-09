//
//  DatabseConnector.swift
//  MessageProxy
//
//  Created by Salman Husain on 3/1/17.
//  Copyright © 2017 Salman Husain. All rights reserved.
//

import Foundation
import GRDB
import Contacts

class DatabaseConstructor: NSObject {
    private var databaseQueue:DatabaseQueue?; //Our database
    private var contactsDatabase:[String:String]? //
    
    /// Make an init with a special database. Should be used!
    ///
    /// - Parameter datebaseLocation: The path to the iMessage database
    init(datebaseLocation:String) throws {
        super.init()
        databaseQueue =  try DatabaseQueue(path: datebaseLocation)
        
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
                let rows = try Row.fetchAll(db, "SELECT * from chat_handle_join JOIN handle ON handle.ROWID = chat_handle_join.handle_id JOIN chat on chat.ROWID =  chat_handle_join.chat_id")
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
				oldConversation!.setValue(oldParticipants + ", " + conversation.value(named: "id"), forKey: "IDs")
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
                if (displayName as! String != "") {
                    conversationDictionaryRepresentation.setValue(conversation.value(named: "display_name"), forKey: "display_name")
                    conversationDictionaryRepresentation.setValue(false, forKey: "has_manual_display_name") //The display name is a real named iMessage group and so it must be used as the send to in the client
                }else {
                    //No, we don't so let's build the human one
                    conversationDictionaryRepresentation.setValue(getHumanName(handle_id: conversation.value(named: "handle_id")), forKey: "display_name")
                    conversationDictionaryRepresentation.setValue(true, forKey: "has_manual_display_name")
                }
				
				//Add our last message. This gives us a blurb, last date, etc
				conversationDictionaryRepresentation.setValue(getMessages(forChatID: conversation.value(named: "chat_id"), messageLimit: 1).firstObject, forKey: "lastMessage")
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
		let task = Process()
		task.launchPath = "/usr/bin/osascript"
		//Set up the arguments!
		task.arguments = [Bundle.main.path(forResource: "messageSender", ofType: "scpt")!,withMessage,toRecipients]
		task.launch()
	}
    
    
    //Holds a reference to the last rowid of the message we've seen. Used to know when we have to notify about new messages.
    var lastMessageDate = 0;
    /// Called by a global timer which checks if we have any new messages
    func checkForNewMessages() {
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
                try messageNewMessageRows?.forEach({
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
                        let postDictionary = ["value1":senderName,"value2":newMessage.value(named: "text"),"value3":handleTable[Int(handleID!)]?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)]
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
