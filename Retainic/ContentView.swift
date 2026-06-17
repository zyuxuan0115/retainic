//
//  ContentView.swift
//  Retainic
//
//  Root view. Gates: language onboarding -> sign in -> main app.
//

import SwiftUI

struct ContentView: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                AuthView()
            } else {
                MainTabView()
            }
        }
        // Drive the whole interface from the preferred-language setting.
        .environment(\.locale, Locale(identifier: Language.localeIdentifier(for: preferredLanguage)))
    }
}

enum AppStorageKey {
    static let preferredLanguage = "preferredLanguage"
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
