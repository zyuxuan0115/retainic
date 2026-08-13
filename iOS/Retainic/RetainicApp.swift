//
//  RetainicApp.swift
//  Retainic
//
//  Created by Yuxuan Zhang on 6/13/26.
//

import SwiftUI
import FirebaseCore

@main
struct RetainicApp: App {
    @StateObject private var auth = AuthService()

    init() {
        FirebaseApp.configure()
        // Both before anything reads or writes: the cache settings only take
        // effect while Firestore is untouched, and the repositories consult
        // the network path on their very first call.
        FirestoreOffline.configure()
        Connectivity.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}
