//
//  SettingsView.swift
//  Retainic
//
//  Account info, language preferences, and sign out.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

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
                    Picker("Native language", selection: $nativeLanguage) {
                        ForEach(Language.all) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showingSignOut = true
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of Retainic?", isPresented: $showingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthService())
}
