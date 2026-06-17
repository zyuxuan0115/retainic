//
//  SettingsView.swift
//  Retainic
//
//  Account info, language preferences, and sign out.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    @EnvironmentObject private var auth: AuthService
    @State private var showingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Username", value: auth.profile?.username ?? auth.displayName ?? "—")
                    LabeledContent("Email", value: auth.profile?.email ?? auth.email ?? "—")
                }

                Section("Language") {
                    Picker("Preferred language", selection: $preferredLanguage) {
                        ForEach(Language.all) { language in
                            Text(language.autonym).tag(language.code)
                        }
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showingSignOut = true
                    }
                }
            }
            .navigationTitle("Settings".localized(preferredLanguage))
            .confirmationDialog("Sign out of Retainic?".localized(preferredLanguage), isPresented: $showingSignOut, titleVisibility: .visible) {
                Button("Sign Out".localized(preferredLanguage), role: .destructive) { auth.signOut() }
                Button("Cancel".localized(preferredLanguage), role: .cancel) {}
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthService())
}
