# Retainic — Android

A native Android port of the Retainic vocabulary-learning app, built with
**Kotlin + Jetpack Compose (Material 3)** and **Firebase**. It talks to the
**same Firebase project** (`retainic-85b91`) as the iOS and web clients, so an
account and its lists, words, pronunciations, review progress, and stats are
shared across all three.

It reproduces the iOS app's interface and functionality:

- **Email/password accounts** with the same invitation-code registration gate.
- **Localized interface** in English, Spanish, Chinese, Japanese, and Korean,
  driven by a **Preferred language** setting (defaults to the device language).
- **Vocabulary lists** with a learning + original language pair, a Trash
  (soft-delete / restore / purge), and **share / import by unique ID**.
- **Rich word entries**: term, translation, one or more parts of speech,
  pinyin (Chinese) or hiragana (Japanese) readings, a **recorded pronunciation**
  (Firebase Storage), optional **text-to-speech** fallback, and notes.
- **Bulk select** to delete or **move** words to a compatible list (progress and
  audio preserved).
- **Flashcard practice** — Daily assignment (only cards due today under each
  aspect's spaced-repetition schedule) or Free practice; multi-select "Show
  first" (Word / Translation / Audio); flip, grade "Got It" / "Practice Again",
  missed cards re-queued.
- **Per-aspect spaced repetition** (spelling, translation, pronunciation) using
  the exact same review-gap schedules and mastery thresholds as iOS.
- **Statistics** — total memorized, "Remembered today" bar chart, "This week"
  trend lines, and average pace per day / week / month.

## Requirements

- **Android Studio** (Ladybug / 2024.2 or newer) with the Android SDK.
- **JDK 17** (bundled with recent Android Studio).
- Minimum device / emulator: **Android 8.0 (API 26)**.

## Firebase setup

The repo ships a `app/google-services.json` derived from the shared project so
the app compiles out of the box. For a real device build you should register a
dedicated **Android app** in Firebase and drop in its own config:

1. In the [Firebase console](https://console.firebase.google.com/) open the
   **retainic-85b91** project → **Add app → Android**.
2. Use the package name **`com.retainic.app`** (or change `applicationId` in
   `app/build.gradle.kts` and match it here).
3. Download the generated **`google-services.json`** and replace
   `app/google-services.json` with it.
4. Make sure **Authentication → Email/Password** is enabled and **Firestore**
   and **Storage** exist (they already do — this is the shared backend).

> Registration is gated by an **invitation code**. Codes live as document IDs
> under the `invitationCodes` collection (added via the Firebase console or Admin
> SDK). You need a valid code to create an account, exactly as on iOS/web.

The Firestore and Storage security rules are shared and live in the top-level
[`firebase/`](../firebase) folder.

## Build & run

Open the `android/` folder in Android Studio and let it sync Gradle (this also
generates the Gradle wrapper). Then pick an emulator or device and **Run**.

From the command line (after Android Studio has generated the wrapper, or with a
local Gradle 8.11+):

```bash
cd android
./gradlew installDebug
```

> Pronunciation recording needs the **microphone** permission, which the app
> requests on first record. The emulator can record from your computer's mic if
> host audio input is enabled.

## Project structure

```
app/src/main/java/com/retainic/app/
├── RetainicApp.kt            Application; initializes the audio/TTS store
├── MainActivity.kt           Locale override + Compose entry, language CompositionLocals
├── data/
│   ├── Models.kt             Firestore models + per-aspect spaced-repetition logic
│   ├── VocabRepository.kt    Firestore + Storage read/write helpers
│   ├── AuthService.kt        Firebase Auth + profile (ViewModel)
│   └── PartOfSpeech.kt       Parts of speech + localized labels
├── audio/AudioManager.kt     Recording, playback, and text-to-speech
├── i18n/
│   ├── Language.kt           Supported languages + display names
│   └── Prefs.kt              Preferred-language storage + locale wrapping
└── ui/                       Compose screens and navigation
    ├── ListDetailScreen.kt       Word-list state and interaction coordinator
    ├── ListDetailComponents.kt   Word row, settings, and bulk-move dialogs
    └── Components.kt             Shared empty, loading, error, and POS controls
app/src/main/res/values*/strings.xml   UI translations (en, es, zh, ja, ko)
```

Field names in `Models.kt` match the iOS Firestore documents exactly (including
the historical `Pronounciation` spellings and the snake_case `remember_final`)
so both clients read and write the same data.
