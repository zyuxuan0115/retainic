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
- **Create from a CSV** *(web only)* — **New List ▸ Import CSV** seeds a new list
  from a file. Columns are `word, translation, notes, part of speech, hiragana,
  pinyin`; a header row is optional and, when present, columns are matched by
  name — so a CSV exported from the app (localized headers, single *Reading*
  column) imports straight back. Parts of speech are recognized in any of the
  interface languages (`Noun`, `Sustantivo`, `名词`, `名詞`, `명사`). Rows that
  don't match the format are skipped and counted: no word, a part of speech
  that isn't one, or data in a column the file doesn't name.
- **Glossaries** — a separate **My Glossaries** dashboard for single-language
  reference decks: each entry is a term and its definitions (plus optional
  notes), with no translation language, readings or recordings. A term can mean
  several things: every definition is scheduled and practised on its own, so a
  term with five definitions is five cards when the definition comes first, and
  one card revealing them all the other way round. Glossaries are independent of
  vocabulary lists — their own documents, screens and practice — but they share
  the Trash and the spaced-repetition schedule, practising two methods (*Term*
  and *Definition*) instead of three.
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
- **Statistics** — words and glossary terms memorized, *Remembered today* bar chart, *This week*
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
├── package.json            Dependency-free Node test command
├── tests/                  Translation and module-size regression checks
└── js/
    ├── app.js              App boot, tab shell, and navigation coordinator
    ├── ui.js               Shared DOM controls, feedback, audio, and icons
    ├── screens/            Feature-focused screen and sheet modules
    ├── firebase.js         Firebase Web SDK init (shared project config)
    ├── auth.js             Email/password auth + profile (AuthService.swift)
    ├── repository.js       Firestore/Storage CRUD (VocabRepository.swift)
    ├── models.js           Word model + spaced-repetition logic (FirestoreModels.swift)
    ├── glossary.js         Glossary entry model on the same review schedule
    ├── csv.js              CSV escaping/parsing shared by the list export and import
    ├── audio.js            Recording + playback (AudioManager.swift)
    ├── i18n.js             Language list + string lookup (Language/AppLanguage.swift)
    ├── translations.js     Locale-dictionary index
    ├── translations/       Feature-oriented chunks of the generated UI strings
    └── dom.js              Tiny DOM/sheet helpers
```

Run the dependency-free regression suite with `npm test`; it checks translation
parity and enforces the repository's 600-line source-module ceiling.
