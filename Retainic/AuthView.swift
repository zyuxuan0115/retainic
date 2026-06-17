//
//  AuthView.swift
//  Retainic
//
//  Login / registration screen. Shown when no user is signed in.
//

import SwiftUI

struct AuthView: View {
    enum Mode: String, CaseIterable {
        case login = "Log In"
        case register = "Register"
    }

    @EnvironmentObject private var auth: AuthService

    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    private var isRegistering: Bool { mode == .register }

    private var isValid: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passwordOK = password.count >= 6
        let usernameOK = !isRegistering || !username.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOK && passwordOK && usernameOK
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 14) {
                        if isRegistering {
                            field("Username", text: $username, systemImage: "person")
                                .textInputAutocapitalization(.never)
                        }
                        field("Email", text: $email, systemImage: "envelope")
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                        secureField("Password", text: $password)
                    }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        HStack {
                            if auth.isWorking { ProgressView().tint(.white) }
                            Text(isRegistering ? "Create Account" : "Log In")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid || auth.isWorking)

                    if isRegistering {
                        Text("Password must be at least 6 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(isRegistering ? "Create Account" : "Welcome Back")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, _ in auth.errorMessage = nil }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Retainic")
                .font(.largeTitle.bold())
            Text("Sign in to access your vocabulary lists.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private func field(_ title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 24)
            TextField(title, text: text)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 24)
            SecureField(title, text: text)
                .textContentType(isRegistering ? .newPassword : .password)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        let email = self.email.trimmingCharacters(in: .whitespaces)
        Task {
            if isRegistering {
                await auth.register(email: email, password: password, username: username.trimmingCharacters(in: .whitespaces))
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthService())
}
