# Retainic

Retainic is a vocabulary-learning app. You create vocabulary lists, add the words
you're studying (with translations, readings, parts of speech, and a recorded
pronunciation), then practice them with spaced-repetition flashcards. Each word is
reviewed along three independent tracks — **spelling**, **translation**, and
**pronunciation** — and the app charts your progress over time.

There are three clients — native iOS and Android apps plus a browser app — that
share the **same Firebase project** (`retainic-85b91`), so your accounts, lists,
words, pronunciations, review progress, and stats are the same everywhere.
Sign in on any client and your data is there.

## Repository layout

```
iOS/         Native SwiftUI + Firebase iOS app
android/     Native Jetpack Compose + Firebase Android app
web/         Dependency-free single-page web app (ES modules + Firebase Web SDK)
firebase/    Shared Firebase backend config: security rules, indexes, CLI config
```

Each folder has its own README with setup and build instructions:

- [`iOS/README.md`](iOS/README.md) — requirements, Firebase setup, building and
  running in Xcode.
- [`android/README.md`](android/README.md) — requirements, Firebase setup, and
  Android Studio/Gradle build instructions.
- [`web/README.md`](web/README.md) — running the web app locally and its feature
  parity with iOS.
- [`firebase/README.md`](firebase/README.md) — the Firestore/Storage security
  rules and how to deploy them with the Firebase CLI.

## Architecture

All three clients talk directly to Firebase:

- **Firebase Authentication** — email/password accounts; each user's data is
  private to them.
- **Cloud Firestore** — vocabulary lists, words, and daily stats, scoped per
  user (`users/{uid}/...`).
- **Cloud Storage** — recorded pronunciations.

Access is restricted per user by the security rules in `firebase/`, which are the
single source of truth shared by all three clients. App-level SDK config
(`GoogleService-Info.plist` for iOS, `google-services.json` for Android, and the
config object in `web/js/firebase.js`) lives with each app.
