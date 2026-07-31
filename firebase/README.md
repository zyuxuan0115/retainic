# Firebase backend config

Shared Firebase project configuration and security rules for Retainic, used by
the web (`../web`), iOS (`../iOS`), and Android (`../android`) apps. This is the single
source of truth for the backend rules — deploy from here, not from any app
folder.

```
.firebaserc              Firebase project alias (default: retainic-85b91)
firebase.json            Firebase CLI config (points at the rules/indexes below)
firestore.rules          Per-user Firestore access rules
firestore.indexes.json   Firestore index / field-override definitions
storage.rules            Per-user Cloud Storage access rules
```

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
`android/app/google-services.json`, and the config object in `web/js/firebase.js`)
stays with each app — only the backend rules and CLI config live here.

## Word fact compatibility

Word documents keep two fields for backward compatibility across independently
updated clients:

- `translation`: a required, non-empty string containing the first related fact.
- `translations`: an optional ordered array of all related facts.

Updated clients prefer `translations`, fall back to `translation` for legacy
documents, and write both fields. Do not remove or change the scalar field to an
array: older Swift/Kotlin decoders require it to remain a string.
