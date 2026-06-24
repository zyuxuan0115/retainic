# Retainic

Retainic is an iOS vocabulary-learning app built with SwiftUI and Firebase. You
create vocabulary lists, add the words you're studying (with translations,
readings, parts of speech, and even a recorded pronunciation), then practice them
with spaced-repetition flashcards. Each word is reviewed along three independent
tracks — spelling, translation, and pronunciation — and the app charts your
progress over time.

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
  are offered as destinations). Moving a word preserves its review progress and
  pronunciation audio.
- **Flashcard practice** — flip-card review with two modes:
  - **Daily assignment** — surfaces only the cards that are *due* today under
    each word's spaced-repetition schedule.
  - **Free practice** — review every word that isn't fully mastered yet,
    regardless of schedule (this mode doesn't affect your stats).

  You pick what the front of the card shows with **Show first**, and you can
  select more than one at a time:
  - **Word** (the term),
  - **Translation**, or
  - **Audio** (listen and recall — only words with a recording are included).

  Each selected aspect a word still owes today becomes its own card, so one word
  can show up several times in a session (e.g. once for its translation and once
  for its audio). Flipping a card reveals the full entry, and you grade yourself
  "Got It" or "Practice Again." Missed cards are re-queued later in the same
  session.
- **Per-aspect spaced repetition** — spelling, translation, and pronunciation
  are each scheduled separately with their own widening review gaps. A word is
  **mastered** ("finally remembered") once every aspect has been recalled enough
  times — and only then does it drop out of practice.
- **Statistics** — a dashboard powered by Swift Charts:
  - total words **memorized** out of your total,
  - a **Remembered today** bar chart broken down by aspect,
  - a **This week** trend line per aspect, and
  - your **average pace** per day / week / month since you started.

---

## Tech stack

- **SwiftUI** (iOS app)
- **Swift Charts** — statistics dashboard
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
users/{uid}/lists/{listId}/words/{wordId}   -> VocabWord (term, translation, …,
                                                 per-aspect review progress)
users/{uid}/dailyStats/{yyyy-MM-dd}         -> DailyStat (per-aspect remembered counts)

Firebase Storage:
users/{uid}/lists/{listId}/words/{wordId}/pronunciation.m4a
```

Each word tracks its review progress per aspect (correct counts and last-correct
dates for spelling, translation, and pronunciation), plus a legacy Leitner box
used by the "memorized" statistic. `dailyStats` documents are keyed by date and
hold how many words were remembered per aspect that day, feeding the trend chart.

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
├── FlashcardView.swift      Spaced-repetition practice session (daily / free, multi-mode)
├── StatsView.swift          Statistics dashboard (Swift Charts)
├── SettingsView.swift       Account, language, sign out
├── VocabRepository.swift    Firestore + Storage read/write helpers (incl. daily stats)
├── FirestoreModels.swift    Data models + per-aspect spaced-repetition helpers
├── AudioManager.swift       Pronunciation recording/playback
├── Language.swift           Supported languages
├── AppLanguage.swift        Looks up UI strings in a specific language's bundle
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
- Two related-but-distinct ideas appear in the app:
  - **Memorized** (the big number on the Statistics screen) means a word has
    graduated to the final Leitner box — see `VocabWord.isMemorized` in
    `FirestoreModels.swift`.
  - **Finally remembered** (`remember_final`) means every aspect has been
    recalled enough times under its own schedule; such words are excluded from
    practice. The thresholds live in `VocabWord.updateRememberFinal`.
- The per-aspect review schedules (`wordReviewGaps`, `translationReviewGaps`,
  `pronunciationReviewGaps`) in `FirestoreModels.swift` control how many days
  pass between reviews as a word is recalled more often.
