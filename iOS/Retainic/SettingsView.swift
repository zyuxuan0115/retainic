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
    @State private var showingChangePassword = false

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
                    Button("Change Password") {
                        showingChangePassword = true
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
            .sheet(isPresented: $showingChangePassword) {
                ChangePasswordView()
                    .environmentObject(auth)
                    .preferredLocale(preferredLanguage)
            }
        }
    }
}

/// Sheet to change the account password. The user must enter their current
/// password correctly (verified by reauthentication) before the new one is set.
struct ChangePasswordView: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var localError: String?

    /// Save is allowed only once the current password is entered, the new one is
    /// long enough, and the confirmation matches.
    private var canSave: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6
            && confirmPassword == newPassword && !auth.isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current password") {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                }
                Section {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("New password")
                } footer: {
                    Text("Password must be at least 6 characters.")
                }
                Section("Confirm new password") {
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
                if let message = localError ?? auth.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Change Password".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { auth.errorMessage = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized(preferredLanguage)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized(preferredLanguage)) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        localError = nil
        guard newPassword == confirmPassword else {
            localError = "The new passwords don't match.".localized(preferredLanguage)
            return
        }
        Task {
            let ok = await auth.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            if ok { dismiss() }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthService())
}
