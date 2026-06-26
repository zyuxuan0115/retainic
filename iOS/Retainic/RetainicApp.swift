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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}
