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
        .preferredLocale(preferredLanguage)
    }
}

enum AppStorageKey {
    static let preferredLanguage = "preferredLanguage"
}

extension View {
    /// Applies the app's preferred-language locale to the interface. Also use
    /// this on presented sheets, which don't reliably inherit `\.locale` from
    /// the presenting view, so they'd otherwise fall back to the system language.
    func preferredLocale(_ code: String) -> some View {
        environment(\.locale, Language.locale(for: code))
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
