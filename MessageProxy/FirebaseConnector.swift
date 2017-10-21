//
//  FirebaseConnector.swift
//  MessageProxy
//
//  Created by Salman Husain on 10/20/17.
//  Copyright © 2017 Salman Husain. All rights reserved.
//

import Foundation
import FirebaseCommunity


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
                self.userTableReference.observe(.value, with: { snapshot in
                    //fprint(snapshot.value)
                })
            }else{
                fprint("Missing user data structure -- prepare")
                self.createUserStructure()
            }
            
            self.onReadyCallback!(true,"")
            
            
        })
        
        //print("[Firebase]: \(ref.child("tesa").value(forKey: "test???"))")
    }
    
    func createUserStructure() {
        userTableReference.child("conversations").setValue(["__meta_prepared" : true])
        userTableReference.child("messages").setValue(["__meta_prepared" : true])
        userTableReference.child("outbox").setValue(["__meta_prepared" : true])
        userTableReference.child("metadata").setValue(["__meta_prepared" : true])
    }
    func updateConversations(conversation: NSArray) {
        fprint("updating..")
        userTableReference.child("conversations").setValue(conversation)
        fprint("done")
    }
    
   
}

func fprint(_ value: Any?) {
    let string = "[Firebase] \(value ?? "nil")"
    string.enumerateLines { (line, _) in
        print("[Firebase] \(line)")
    }
}
