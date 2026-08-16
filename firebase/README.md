# Firebase backend config

Shared Firebase project configuration and security rules for Retainic, used by
**all three** clients: the iOS app (`../iOS`), the Android app (`../android`),
and the web app (`../web`). This is the single source of truth for the backend
rules — deploy from here, not from any app folder.

```
.firebaserc              Firebase project alias (default: retainic-85b91)
firebase.json            Firebase CLI config (points at the rules/indexes below)
firestore.rules          Per-user Firestore access rules
firestore.indexes.json   Firestore index / field-override definitions
storage.rules            Per-user Cloud Storage access rules
```

## What the rules allow

- Everything under `users/{uid}` — lists, words, glossaries, entries, daily
  stats — is readable and writable only by that signed-in user.
- Any signed-in user may **read** documents in a `lists` or `words` collection
  wherever they live, which is what makes importing a list shared by its public
  ID work. Writes stay owner-only.
- `invitationCodes/{code}` allows `get` (so the app can verify a code someone
  already knows before registration) but never `list` or write; codes are added
  from the Firebase console or the Admin SDK.
- Storage mirrors this: only the owner can read or write
  `users/{uid}/lists/…/pronunciation.m4a`.

## Deploy

```bash
# one-time setup
npm install -g firebase-tools
firebase login

# from this folder
firebase use --add          # select your Firebase project (first time only)
firebase deploy --only firestore:rules,firestore:indexes,storage
```

App-level SDK config (`GoogleService-Info.plist` for iOS,
`android/app/google-services.json` for Android, and the config object in
`web/js/firebase.js`) stays with each app — only the backend rules and CLI
config live here.
