# Graph Report - .  (2026-07-31)

## Corpus Check
- 66 files · ~81,507 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 788 nodes · 1725 edges · 40 communities (38 shown, 2 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 52 edges (avg confidence: 0.8)
- Token cost: 54,500 input · 4,268 output

## Community Hubs (Navigation)
- Web App UI & Algorithm Editor
- iOS Auth Service & Profile
- Web Firebase Data Layer
- iOS List Detail & Word Editing
- iOS Firestore Data Models
- Android Vocab Repository
- iOS Vocab Lists & Sharing
- iOS Audio Playback & TTS
- iOS Flashcard Practice Session
- Android Spaced Repetition Models
- Web Spaced Repetition Models
- Android Audio Playback & TTS
- Cross-Platform Architecture Docs
- Web Audio Playback & Recording
- Android App Shell & Theme
- Android Flashcard Practice Screen
- Android List Detail Screen
- Android List & Trash Screens
- Android Stats Charts
- iOS Stats Data Aggregation
- Android Auth Service
- Android Part Of Speech Enum
- Android Navigation Scaffold
- iOS Auth View
- iOS Stats Presentation
- iOS Add Word View
- iOS Part Of Speech Enum
- iOS Root Views & Tabs
- Android Locale Preferences
- Android Settings Screen
- Android Language Enum
- Android Add Word Screen
- iOS App Entry Point
- iOS Settings & Password
- App Icon Memory Concepts
- Android Application Class
- Android About Screen

## God Nodes (most connected - your core abstractions)
1. `String` - 117 edges
2. `el()` - 39 edges
3. `VocabRepository` - 32 edges
4. `t()` - 30 edges
5. `VocabRepository` - 29 edges
6. `View` - 27 edges
7. `FlashcardView` - 26 edges
8. `ListDetailView` - 25 edges
9. `icon()` - 25 edges
10. `PronunciationRecorder` - 22 edges

## Surprising Connections (you probably didn't know these)
- `Kotlin + Jetpack Compose (Material 3) stack` --semantically_similar_to--> `SwiftUI + Firebase iOS tech stack`  [INFERRED] [semantically similar]
  android/README.md → iOS/README.md
- `ListDetailScreen()` --calls--> `PracticeCard`  [INFERRED]
  android/app/src/main/java/com/retainic/app/ui/ListDetailScreen.kt → android/app/src/main/java/com/retainic/app/data/Models.kt
- `Shared Firebase project retainic-85b91` --conceptually_related_to--> `Backend rules single source of truth`  [INFERRED]
  README.md → firebase/README.md
- `Per-aspect spaced repetition (widening review gaps)` --conceptually_related_to--> `Three independent review tracks (spelling, translation, pronunciation)`  [INFERRED]
  iOS/README.md → README.md
- `Backend rules single source of truth` --conceptually_related_to--> `Per-user data scoping (users/{uid}/...)`  [INFERRED]
  firebase/README.md → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Three clients share one Firebase project and backend rules** — ios_readme_retainic, web_readme_retainic, android_readme_retainic, readme_shared_firebase_project, firebase_readme_backend_config [EXTRACTED 1.00]
- **Per-aspect spaced repetition across spelling/translation/pronunciation with mastery states** — readme_three_review_tracks, ios_readme_per_aspect_spaced_repetition, ios_readme_memorized_leitner, ios_readme_finally_remembered [INFERRED 0.85]
- **Cross-client Firestore/Storage data compatibility** — ios_readme_data_model, android_readme_field_name_compat, web_readme_mediarecorder_audio [INFERRED 0.85]

## Communities (40 total, 2 thin omitted)

### Community 0 - "Web App UI & Algorithm Editor"
Cohesion: 0.08
Nodes (89): RFC-4180, compileAlgorithm(), pyodide(), useAlgorithm(), useDefaultAlgorithm(), AboutScreen(), audioButton(), AuthScreen() (+81 more)

### Community 1 - "iOS Auth Service & Profile"
Cohesion: 0.08
Nodes (23): AuthStateDidChangeListenerHandle, CollectionReference, DateFormatter, Error, Firestore, String, AuthService, Bool (+15 more)

### Community 2 - "Web Firebase Data Layer"
Cohesion: 0.09
Nodes (43): authState, friendlyMessage(), onAuthChange(), register(), app, db, firebaseConfig, storage (+35 more)

### Community 3 - "iOS List Detail & Word Editing"
Cohesion: 0.07
Nodes (23): EditMode, ListDetailView, ListSettingsSheet, MoveDestinationSheet, AuthService, Binding, Bool, IndexSet (+15 more)

### Community 4 - "iOS Firestore Data Models"
Cohesion: 0.12
Nodes (20): Codable, Combine, CryptoKit, FirebaseAuth, FirebaseFirestore, FirebaseStorage, Foundation, Identifiable (+12 more)

### Community 5 - "Android Vocab Repository"
Cohesion: 0.13
Nodes (7): DailyStat, DocumentReference, SharedList, VocabularyList, VocabWord, VocabRepository, ByteArray

### Community 6 - "iOS Vocab Lists & Sharing"
Cohesion: 0.10
Nodes (18): Hashable, ListRow, ListsViewModel, Mode, create, importById, NewListSheet, AuthService (+10 more)

### Community 7 - "iOS Audio Playback & TTS"
Cohesion: 0.12
Nodes (13): AVAudioPlayer, AVAudioPlayerDelegate, AVAudioRecorder, AVFoundation, AVSpeechSynthesizer, AVSpeechSynthesizerDelegate, AVSpeechUtterance, AudioPlaybackStore (+5 more)

### Community 8 - "iOS Flashcard Practice Session"
Cohesion: 0.10
Nodes (16): CardView, FlashcardView, FrontMode, pronunciation, term, translation, SessionItem, AuthService (+8 more)

### Community 9 - "Android Spaced Repetition Models"
Cohesion: 0.12
Nodes (13): DailyStat, daysBetween(), isDue(), isSameDay(), PartOfSpeech, MemoryStat, PracticeCard, SharedList (+5 more)

### Community 10 - "Web Spaced Repetition Models"
Cohesion: 0.14
Nodes (17): daysBetween(), isPronunciationDue(), isSameDay(), isToday(), isTranslationDue(), isWordDue(), markCorrect(), markIncorrect() (+9 more)

### Community 11 - "Android Audio Playback & TTS"
Cohesion: 0.17
Nodes (7): AudioPlaybackStore, Context, PronunciationRecorder, CoroutineScope, MediaPlayer, MediaRecorder, TextToSpeech

### Community 12 - "Cross-Platform Architecture Docs"
Cohesion: 0.14
Nodes (23): Field-name compatibility with iOS Firestore documents (Pronounciation, remember_final), Invitation-code registration gate (invitationCodes collection), Kotlin + Jetpack Compose (Material 3) stack, Retainic Android app README, Firebase backend config (shared security rules), Backend rules single source of truth, Firestore data model (users/lists/words/dailyStats), Finally remembered (remember_final, updateRememberFinal) (+15 more)

### Community 13 - "Web Audio Playback & Recording"
Cohesion: 0.17
Nodes (6): AudioPlaybackStore, playback, PronunciationRecorder, recorderOptions(), ttsBcp47(), audioURL()

### Community 14 - "Android App Shell & Theme"
Cohesion: 0.12
Nodes (10): Context, MainActivity, AuthScreen(), AuthService, AuthService, RootView(), RetainicTheme(), Bundle (+2 more)

### Community 15 - "Android Flashcard Practice Screen"
Cohesion: 0.18
Nodes (16): FlashcardScreen(), FlipCard(), FrontMode, PRONUNCIATION, TERM, TRANSLATION, IconButton_Back(), AuthService (+8 more)

### Community 16 - "Android List Detail Screen"
Cohesion: 0.18
Nodes (15): EmptyState(), AuthService, Modifier, VocabularyList, VocabWord, ListDetailScreen(), ListSettingsDialog(), MoveDestinationDialog() (+7 more)

### Community 17 - "Android List & Trash Screens"
Cohesion: 0.20
Nodes (12): LoadingView(), AuthService, Modifier, TrashScreen(), ErrorDialog(), AuthService, Modifier, VocabularyList (+4 more)

### Community 18 - "Android Stats Charts"
Cohesion: 0.25
Nodes (13): BarChart(), buildWeekPoints(), countTodayRemembered(), AuthService, Color, Modifier, VocabWord, LearningStats (+5 more)

### Community 19 - "iOS Stats Data Aggregation"
Cohesion: 0.25
Nodes (9): Charts, AspectBar, DayAspectPoint, LearningStats, StatsViewModel, DailyStat, Date, Int (+1 more)

### Community 20 - "Android Auth Service"
Cohesion: 0.24
Nodes (4): AuthService, UserProfile, AndroidViewModel, FirebaseUser

### Community 21 - "Android Part Of Speech Enum"
Cohesion: 0.17
Nodes (11): fromRaw(), PartOfSpeech, ADJECTIVE, ADVERB, CONJUNCTION, INTERJECTION, NOUN, PREPOSITION (+3 more)

### Community 22 - "Android Navigation Scaffold"
Cohesion: 0.29
Nodes (12): Detail, Editor, Home, AuthService, Modifier, ListsNav, ListsRoute, ListsTabContent() (+4 more)

### Community 23 - "iOS Auth View"
Cohesion: 0.21
Nodes (8): CaseIterable, AuthView, Mode, login, register, AuthService, Binding, Bool

### Community 24 - "iOS Stats Presentation"
Cohesion: 0.32
Nodes (6): Double, View, StatsView, AuthService, Color, LocalizedStringKey

### Community 25 - "iOS Add Word View"
Cohesion: 0.27
Nodes (7): AddWordView, AuthService, Bool, PartOfSpeech, Set, VocabWord, Void

### Community 26 - "iOS Part Of Speech Enum"
Cohesion: 0.18
Nodes (10): PartOfSpeech, adjective, adverb, conjunction, interjection, noun, preposition, pronoun (+2 more)

### Community 27 - "iOS Root Views & Tabs"
Cohesion: 0.20
Nodes (6): AboutView, AppStorageKey, ContentView, AuthService, MainTabView, SwiftUI

### Community 28 - "Android Locale Preferences"
Cohesion: 0.38
Nodes (3): Context, LocaleUtil, Prefs

### Community 29 - "Android Settings Screen"
Cohesion: 0.48
Nodes (6): ChangePasswordDialog(), AuthService, Modifier, LabeledRow(), SectionHeader(), SettingsScreen()

### Community 30 - "Android Language Enum"
Cohesion: 0.47
Nodes (3): Language, localeTag(), named()

### Community 31 - "Android Add Word Screen"
Cohesion: 0.40
Nodes (5): AddWordScreen(), AuthService, Modifier, VocabWord, SectionLabel()

### Community 32 - "iOS App Entry Point"
Cohesion: 0.33
Nodes (4): App, FirebaseCore, RetainicApp, Scene

### Community 33 - "iOS Settings & Password"
Cohesion: 0.40
Nodes (4): ChangePasswordView, SettingsView, AuthService, Bool

### Community 34 - "App Icon Memory Concepts"
Cohesion: 0.60
Nodes (5): Retainic App Icon, Forgetting Curve (Ebbinghaus Exponential Decay), Language Learning (Japanese to English), Ring-Bound Notebook / Vocabulary Book Motif, Spaced Repetition / Memory Retention

## Knowledge Gaps
- **56 isolated node(s):** `UserProfile`, `VocabularyList`, `SharedList`, `DailyStat`, `UNSPECIFIED` (+51 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `iOS Auth Service & Profile` to `iOS Settings & Password`, `iOS List Detail & Word Editing`, `iOS Firestore Data Models`, `iOS Vocab Lists & Sharing`, `iOS Audio Playback & TTS`, `iOS Flashcard Practice Session`, `Android App Shell & Theme`, `iOS Stats Data Aggregation`, `iOS Auth View`, `iOS Stats Presentation`, `iOS Add Word View`, `iOS Part Of Speech Enum`, `iOS Root Views & Tabs`?**
  _High betweenness centrality (0.304) - this node is a cross-community bridge._
- **Why does `RootView()` connect `Android App Shell & Theme` to `Android Navigation Scaffold`?**
  _High betweenness centrality (0.162) - this node is a cross-community bridge._
- **Why does `MainScaffold()` connect `Android Navigation Scaffold` to `Android Stats Charts`, `Android About Screen`, `Android Settings Screen`, `Android App Shell & Theme`?**
  _High betweenness centrality (0.162) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `String` (e.g. with `.save()` and `.speechSynthesizer()`) actually correct?**
  _`String` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `UserProfile`, `VocabularyList`, `SharedList` to the rest of the system?**
  _56 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Web App UI & Algorithm Editor` be split into smaller, more focused modules?**
  _Cohesion score 0.07732784259894761 - nodes in this community are weakly interconnected._
- **Should `iOS Auth Service & Profile` be split into smaller, more focused modules?**
  _Cohesion score 0.08283730158730158 - nodes in this community are weakly interconnected._