//
//  ContentView.swift
//  Retainic
//
//  Root view. Gates: language onboarding -> sign in -> main app.
//

import SwiftUI

struct ContentView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""
    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""

    @EnvironmentObject private var auth: AuthService

    var body: some View {
        if nativeLanguage.isEmpty || targetLanguage.isEmpty {
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
    static let targetLanguage = "targetLanguage"
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
