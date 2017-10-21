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
    var ref: DatabaseReference!

    override init() {
        FirebaseApp.configure()
        ref = Database.database().reference(withPath: "users")
        print("[Firebase]: \(ref)")

    }
}
