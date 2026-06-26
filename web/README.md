# Retainic Web

A browser port of the Retainic iOS vocabulary app, with the **same features** and
backed by the **same Firebase project** (`retainic-85b91`) — so accounts and data
are shared across iOS and the web. Sign in with the account you use on iOS and
your lists, words, pronunciations, review progress and stats are all there.

It's a dependency-free single-page app: plain ES modules plus the Firebase Web
SDK loaded from a CDN. No build step.

## Features (parity with iOS)

- **Accounts** — email/password sign up & login (Firebase Auth).
- **Localized UI** — English, Spanish, Chinese, Japanese, Korean (strings
  extracted from the iOS `Localizable.xcstrings`). Change it in **Settings ▸
  Preferred language**; it defaults to the browser language.
- **Vocabulary lists** — create decks with a learning + original language; rename,
  delete, filter (all / remembered / unremembered).
- **Rich word entries** — term, translation, multiple parts of speech, pinyin
  (Chinese) / hiragana (Japanese) readings, recorded pronunciation, notes.
- **Bulk editing** — multi-select words to delete or move to a compatible list
  (same language pair), preserving review progress and audio.
- **Flashcard practice** — daily assignment (per-aspect spaced repetition) and
  free practice, with multi-select *Show first* (Word / Translation / Audio).
  Flip to reveal, grade *Got It* / *Practice Again*; missed cards re-queue.
- **Per-aspect spaced repetition** — spelling, translation and pronunciation are
  scheduled independently; the schedules and mastery thresholds match the iOS
  app exactly (see `js/models.js`).
- **Statistics** — words memorized, *Remembered today* bar chart, *This week*
  trend lines, and average pace per day / week / month (SVG charts, no library).

## Running it

ES modules must be served over HTTP (opening `index.html` from `file://` is
blocked by the browser). From this `web/` folder:

```bash
python3 -m http.server 8000
# then open http://localhost:8000
```

`localhost` is an authorized domain for Firebase Auth by default, so login works
out of the box.

To deploy, host these static files anywhere (Firebase Hosting, Netlify, GitHub
Pages, …) and add your domain under **Firebase console ▸ Authentication ▸
Settings ▸ Authorized domains**.

## Configuration

`js/firebase.js` holds the Web SDK config derived from the iOS
`GoogleService-Info.plist`. The `appId` is the iOS app id; Auth / Firestore /
Storage all work with it. Optionally register a **Web app** in the Firebase
console and paste its `appId` for a dedicated web client.

## Notes & limitations

- **Pronunciation recording** uses the browser `MediaRecorder` API and needs
  microphone permission (and a secure context: `localhost` or HTTPS). Web
  recordings are WebM/Opus uploaded to the same Storage path the iOS app uses.
  The web player handles any format; the iOS app may not play a WebM clip that
  was recorded on the web (and vice-versa for some codecs) — text data and
  review progress always sync regardless.
- **Storage downloads** (moving a word with audio across lists) fetch the file;
  Firebase Storage download URLs are CORS-friendly for this by default.

## Project structure

```
web/
├── index.html              Entry point
├── styles.css              iOS-flavored styling (light/dark)
└── js/
    ├── app.js              All screens + navigation (ports the SwiftUI views)
    ├── firebase.js         Firebase Web SDK init (shared project config)
    ├── auth.js             Email/password auth + profile (AuthService.swift)
    ├── repository.js       Firestore/Storage CRUD (VocabRepository.swift)
    ├── models.js           Word model + spaced-repetition logic (FirestoreModels.swift)
    ├── audio.js            Recording + playback (AudioManager.swift)
    ├── i18n.js             Language list + string lookup (Language/AppLanguage.swift)
    ├── translations.js     UI strings, auto-extracted from Localizable.xcstrings
    └── dom.js              Tiny DOM/sheet helpers
```
