//
//  AuthService.swift
//  Retainic
//
//  Firebase email/password authentication plus the user's profile.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthService: ObservableObject {
    /// The signed-in Firebase user, or nil when logged out.
    @Published var user: User?
    /// The signed-in user's profile (username, email).
    @Published var profile: UserProfile?
    /// Last auth error, shown in the UI.
    @Published var errorMessage: String?
    /// True while a register/login request is in flight.
    @Published var isWorking = false

    private var stateHandle: AuthStateDidChangeListenerHandle?

    var uid: String? { user?.uid }
    var isAuthenticated: Bool { user != nil }
    var displayName: String? { user?.displayName }
    var email: String? { user?.email }

    init() {
        stateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.user = user
                if let uid = user?.uid {
                    Task { await self.loadProfile(uid: uid) }
                } else {
                    self.profile = nil
                }
            }
        }
    }

    // MARK: - Actions

    func register(email: String, password: String, username: String) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            // Store the username on the Firebase user and in the profile document.
            let change = result.user.createProfileChangeRequest()
            change.displayName = username
            try await change.commitChanges()

            let profile = UserProfile(username: username, email: email, createdAt: Date())
            try VocabRepository.userDoc(result.user.uid).setData(from: profile)
            self.profile = profile
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func signOut() {
        errorMessage = nil
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func loadProfile(uid: String) async {
        do {
            let snapshot = try await VocabRepository.userDoc(uid).getDocument()
            profile = try? snapshot.data(as: UserProfile.self)
        } catch {
            // Non-fatal: the UI falls back to the Firebase displayName/email.
        }
    }

    // MARK: - Helpers

    private func friendlyMessage(_ error: Error) -> String {
        // FirebaseAuth error codes (stable public values), mapped to friendly copy.
        switch (error as NSError).code {
        case 17007: return "That email is already registered. Try logging in."
        case 17008: return "Please enter a valid email address."
        case 17026: return "Password must be at least 6 characters."
        case 17009, 17004, 17011: return "Incorrect email or password."
        case 17020: return "Network error. Check your connection and try again."
        default: return error.localizedDescription
        }
    }
}
