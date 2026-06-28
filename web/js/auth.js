//
//  auth.js
//  Retainic Web
//
//  Firebase email/password authentication plus the user's profile. Port of
//  AuthService.swift.
//

import { auth } from "./firebase.js";
import {
  createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut as fbSignOut,
  updateProfile, onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js";
import { createProfile, fetchProfile, isValidInvitationCode } from "./repository.js";
import { t } from "./i18n.js";

export const authState = {
  user: null,
  profile: null,
  get uid() { return this.user?.uid ?? null; },
  get isAuthenticated() { return this.user != null; },
  get email() { return this.user?.email ?? null; },
  get displayName() { return this.user?.displayName ?? null; },
};

/** Subscribe to sign-in/sign-out; callback runs with the current user. */
export function onAuthChange(callback) {
  onAuthStateChanged(auth, async (user) => {
    authState.user = user;
    if (user) {
      try { authState.profile = await fetchProfile(user.uid); } catch { authState.profile = null; }
    } else {
      authState.profile = null;
    }
    callback(user);
  });
}

export async function register(email, password, username, invitationCode) {
  // Gate registration on a valid invitation code before creating the account.
  if (!(await isValidInvitationCode(invitationCode))) {
    const err = new Error("Invalid invitation code.");
    err.code = "app/invalid-invitation";
    throw err;
  }
  const result = await createUserWithEmailAndPassword(auth, email, password);
  await updateProfile(result.user, { displayName: username });
  const profile = { username, email, createdAt: new Date() };
  await createProfile(result.user.uid, profile);
  authState.profile = profile;
}

export async function signIn(email, password) {
  await signInWithEmailAndPassword(auth, email, password);
}

export async function signOut() {
  await fbSignOut(auth);
}

/** Maps Firebase Auth error codes to the same friendly copy the iOS app uses. */
export function friendlyMessage(error) {
  switch (error?.code) {
    case "app/invalid-invitation": return t("That invitation code isn't valid.");
    case "auth/email-already-in-use": return "That email is already registered. Try logging in.";
    case "auth/invalid-email": return "Please enter a valid email address.";
    case "auth/weak-password": return "Password must be at least 6 characters.";
    case "auth/wrong-password":
    case "auth/user-not-found":
    case "auth/invalid-credential": return "Incorrect email or password.";
    case "auth/network-request-failed": return "Network error. Check your connection and try again.";
    default: return error?.message ?? "Something went wrong.";
  }
}
