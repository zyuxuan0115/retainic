# Retainic

Retainic is an iOS vocabulary-learning app built with SwiftUI and Firebase. You
create vocabulary lists, add the words you're studying (with translations,
readings, parts of speech, and even a recorded pronunciation), then practice them
with spaced-repetition flashcards. The app tracks your progress and shows how
many words you've memorized over time.

---

## Features

- **Accounts** — email/password sign up and login (Firebase Authentication).
  Each user's data is private to them.
- **Localized interface** — the whole UI is available in English, Spanish,
  Chinese, Japanese, and Korean. The **Preferred language** (in Settings)
  controls the interface language and defaults to the device's system language.
- **Vocabulary lists** — create as many lists ("decks") as you like. Each list
  has its own **learning language** (the words you study) and **original
  language** (the language you translate into, defaulting to your native
  language).
- **Rich word entries** — every word can include:
  - the term and its translation,
  - one or more **parts of speech**,
  - **pinyin** (for Chinese) or **hiragana** (for Japanese) readings,
  - a **recorded pronunciation** (stored in Firebase Storage),
  - free-form notes.
- **Bulk editing** — multi-select words in a list to **delete** them or **move**
  them to another list (only lists with a matching learning + original language
  are offered as destinations).
- **Flashcard practice** — per-list spaced repetition using the Leitner box
  system. You can choose what the front of the card shows first:
  - **Word** (the term),
  - **Translation**, or
  - **Audio** (listen and recall — only words with a recording are included).

  Flipping a card reveals the full entry, and you grade yourself "Got It" or
  "Practice Again," which updates the word's review schedule.
- **Statistics** — total words memorized plus your average learning pace per
  day / week / month, aggregated across every list.

---

## Tech stack

- **SwiftUI** (iOS app)
- **Firebase** via the [firebase-ios-sdk](https://github.com/firebase/firebase-ios-sdk)
  Swift Package (11.0.0+):
  - **FirebaseAuth** — authentication
  - **FirebaseFirestore** — cloud database
  - **FirebaseStorage** — pronunciation audio
- **AVFoundation** — recording/playing pronunciation audio

### Data model

```
users/{uid}                                 -> UserProfile (username, email)
users/{uid}/lists/{listId}                  -> VocabularyList (name, languages, wordCount)
users/{uid}/lists/{listId}/words/{wordId}   -> VocabWord (term, translation, …, Leitner box)

Firebase Storage:
users/{uid}/lists/{listId}/words/{wordId}/pronunciation.m4a
```

Access is restricted per user by the Firestore and Storage security rules in
`firestore.rules` and `storage.rules`.

---

## Requirements

- **macOS** with **Xcode 26 or later** (the project targets **iOS 26.5**).
- An **Apple ID** for code signing (a free account works for running on the
  simulator or your own device).
- A **Google/Firebase account** to create a Firebase project.
- *(Optional)* the [Firebase CLI](https://firebase.google.com/docs/cli) to
  deploy the security rules.

---

## Build from scratch

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd Retainic
```

### 2. Create a Firebase project

1. Go to the [Firebase console](https://console.firebase.google.com/) and click
   **Add project**. Give it a name and finish the wizard (Analytics optional).

2. **Add an iOS app** to the project:
   - Click the **iOS+** icon on the project overview.
   - Set the **Apple bundle ID**. The project ships with
     `kate0115.Retainic` — either reuse that value, or pick your own bundle ID
     and update it later in Xcode (see step 4).
   - Download the generated **`GoogleService-Info.plist`**.

3. **Replace the config file.** Put your downloaded `GoogleService-Info.plist`
   into the `Retainic/` folder, replacing the existing one:

   ```bash
   cp ~/Downloads/GoogleService-Info.plist Retainic/GoogleService-Info.plist
   ```

   > The bundle ID in this file must match the bundle ID configured in Xcode.

### 3. Enable the Firebase services

In the Firebase console:

- **Authentication** → *Get started* → **Sign-in method** → enable
  **Email/Password**.
- **Firestore Database** → *Create database* (start in production mode; the
  rules in this repo lock it down per user).
- **Storage** → *Get started* (used for pronunciation recordings).

### 4. Open and configure the project in Xcode

```bash
open Retainic.xcodeproj
```

- Xcode resolves the Firebase Swift Package automatically on first open. If it
  doesn't, choose **File ▸ Packages ▸ Resolve Package Versions**.
- Select the **Retainic** target ▸ **Signing & Capabilities**:
  - Choose your **Team**.
  - If you used a custom bundle ID in step 2, set the same
    **Bundle Identifier** here.

### 5. Run

- Pick an **iOS 26.5+ simulator** (or a connected device) and press **⌘R**.
- On first launch you'll register an account. The interface starts in your
  device's language; you can change it later under **Settings ▸ Preferred
  language**.

> **Tip:** Microphone recording does not work on the iOS Simulator by default.
> To test pronunciation recording, enable **I/O ▸ Audio Input** in the
> Simulator, or run on a real device.

---

## Deploying the security rules (optional but recommended)

The repository includes Firestore and Storage rules that restrict each user to
their own data. To deploy them with the Firebase CLI:

```bash
# one-time setup
npm install -g firebase-tools
firebase login

# from the project root
firebase use --add          # select your Firebase project
firebase deploy --only firestore:rules,storage
```

`firebase.json` already points at `firestore.rules` and `storage.rules`.

---

## Project structure

```
Retainic/
├── RetainicApp.swift        App entry point; configures Firebase
├── ContentView.swift        Root gate: sign in → main tabs; applies UI locale
├── AuthService.swift        Firebase Auth + user profile
├── AuthView.swift           Register / login UI
├── MainTabView.swift        Tab bar: My Lists · Statistics · Settings
├── VocabListsView.swift     List of decks + create-list flow
├── ListDetailView.swift     Words in a list; add/edit/delete, bulk move, practice entry
├── AddWordView.swift        Create/edit a word
├── FlashcardView.swift      Spaced-repetition practice session
├── StatsView.swift          Memorization statistics
├── SettingsView.swift       Account, language, sign out
├── VocabRepository.swift    Firestore + Storage read/write helpers
├── FirestoreModels.swift    Data models + Leitner helpers
├── AudioManager.swift       Pronunciation recording/playback
├── Language.swift           Supported languages
├── PartOfSpeech.swift       Parts of speech + localized labels
├── Localizable.xcstrings    UI translations (en, es, zh-Hans, ja, ko)
└── GoogleService-Info.plist Firebase config (replace with your own)

firebase.json                Firebase CLI config
firestore.rules              Per-user Firestore access rules
storage.rules                Per-user Storage access rules
```

---

## Notes

- `GoogleService-Info.plist` contains project identifiers (not secrets), but you
  should still supply your **own** Firebase project's file rather than relying on
  the one in the repo.
- "Memorized" in the statistics means a word has graduated to the final Leitner
  box (box 5) — see `VocabWord.isMemorized` in `FirestoreModels.swift`.
