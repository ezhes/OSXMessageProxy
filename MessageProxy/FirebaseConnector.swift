//
//  FirebaseConnector.swift
//  MessageProxy
//
//  Created by Allison Husain on 10/20/17.
//  Copyright © 2017 Allison Husain. All rights reserved.
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import FirebaseCore

class FirebaseConnector : NSObject {
    var userTableReference: DatabaseReference!
    var currentUser:User?
    private var onReadyCallback:((Bool, String)->Void)?
    
    init(callback:@escaping ((Bool, String)->Void)) {
        super.init()
        FirebaseApp.configure()
        onReadyCallback = callback
        /*Auth.auth().createUser(withEmail: "test@aero2x.eu", password: "") { (user, error) in
            if let error = error {
                print("[Firebase]: auth new \(error)")
            }else {
                print("[Firebase]: auth new √")
            }
        }*/
        
        
        /*Auth.auth().signIn(withEmail: "test2@aero2x.eu", password: "") { (user, error) in
            if let error = error {
                print("[Firebase]: auth error: \(error)")
            }else {
                print("[Firebase]: auth √ \(user!)")
            }
        }*/

    }
    
    func startAuthentication() {
        let handle = Auth.auth().addStateDidChangeListener {  (auth, user) in
            if Auth.auth().currentUser != nil {
                // User is signed in.
                self.currentUser = user
                self.getUserRecords()
            } else {
                self.onReadyCallback!(false,"not authenticated")
                print("[Firebase]: not authernticated")
                
            }
        }
    }
    func getUserRecords() {
        print("[Firebase] \(String(describing: self.currentUser!.uid))")
        userTableReference = Database.database().reference(withPath: "users/" + currentUser!.uid)
        //userTableReference.child("conversations").setValue("test!!!")
        
        userTableReference.observeSingleEvent(of: .value, with: { (snapshot) in
            
            if snapshot.hasChild("conversations"){
                fprint("Ready.")
                self.userTableReference.observeSingleEvent(of: .value, with: { snapshot in
                    //fprint(snapshot.value)
                })
            }else{
                fprint("Missing user data structure -- prepare")
                self.createUserStructure()
            }
            
            self.onReadyCallback!(true,"")
            
            
        })
    }
    
    func getLastMessageRowID(callback:@escaping (Bool, String, Int)->Void) {
        self.userTableReference.child("metadata").observeSingleEvent(of: .value, with: { snapshot in
            if !snapshot.exists() {
                // handle data not found
                callback(false,"Couldn't retrive metadata packet",-111)
                return
            }
            let metadata = snapshot.value as! [String: Any]
            callback(true,"",metadata["last_message"] as! Int)
        })
    }
    
    func addMessage(message:NSDictionary,id:Int,date:Int) {
        fprint("updating..")
        userTableReference.child("messages").updateChildValues(["\(id)" : message])
        userTableReference.child("metadata").updateChildValues(["last_message" : date])
        fprint("done")
    }
    
    func createUserStructure() {
        userTableReference.child("conversations").setValue(["__meta_prepared" : true])
        userTableReference.child("messages").setValue(["__meta_prepared" : true])
        userTableReference.child("outbox").setValue(["__meta_prepared" : true])
        userTableReference.child("metadata").setValue(["__meta_prepared" : true,"last_message" : -1])
    }
    func updateConversations(conversation: NSArray) {
        fprint("updating..")
        userTableReference.child("conversations").setValue(conversation)
        fprint("done")
    }
    
   
}

func fprint(_ value: Any?) {
    let string = "\(value ?? "nil")"
    string.enumerateLines { (line, _) in
        print("[Firebase] \(line)")
    }
}
