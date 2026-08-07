# Firebase backend config

Shared Firebase project configuration and security rules for Retainic, used by
**both** the iOS app (`../iOS`) and the web app (`../web`). This is the single
source of truth for the backend rules — deploy from here, not from either app
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

App-level SDK config (`GoogleService-Info.plist` for iOS, the config object in
`web/js/firebase.js`) stays with each app — only the backend rules and CLI
config live here.
