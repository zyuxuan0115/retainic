//
//  ContentView.swift
//  Retainic
//
//  Root view. Gates: language onboarding -> sign in -> main app.
//

import SwiftUI

struct ContentView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

    @EnvironmentObject private var auth: AuthService

    var body: some View {
        if nativeLanguage.isEmpty {
            OnboardingView()
        } else if !auth.isAuthenticated {
            AuthView()
        } else {
            MainTabView()
        }
    }
}

enum AppStorageKey {
    static let nativeLanguage = "nativeLanguage"
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
