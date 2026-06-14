//
//  ContentView.swift
//  Retainic
//
//  Root view: shows onboarding until languages are chosen, then the main app.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""
    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""

    var body: some View {
        if nativeLanguage.isEmpty || targetLanguage.isEmpty {
            OnboardingView()
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
        .modelContainer(for: Word.self, inMemory: true)
}
