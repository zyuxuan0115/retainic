//
//  FirestoreModels.swift
//  Retainic
//
//  Cloud (Firestore) data models. Replaces the former local SwiftData model.
//
//  Layout:
//    users/{uid}                         -> UserProfile
//    users/{uid}/lists/{listId}          -> VocabularyList
//    users/{uid}/lists/{listId}/words/{} -> VocabWord
//

import Foundation
import FirebaseFirestore

/// Account profile created at registration.
struct UserProfile: Codable {
    var username: String
    var email: String
    var createdAt: Date
}

/// A named vocabulary list (deck) owned by a user.
struct VocabularyList: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date
    var wordCount: Int
    /// Language of the words being studied (the `term` side). Drives the
    /// pinyin/hiragana reading. Optional so older documents still decode.
    var learningLanguage: String?
    /// Language the words are translated into (the `translation` side).
    /// Optional so older documents still decode.
    var originalLanguage: String?

    init(
        id: String? = nil,
        name: String,
        createdAt: Date,
        wordCount: Int,
        learningLanguage: String? = nil,
        originalLanguage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.wordCount = wordCount
        self.learningLanguage = learningLanguage
        self.originalLanguage = originalLanguage
    }
}

/// Memory stats for one aspect of a word (translation, pronunciation, or
/// spelling): how many times it was tested, how many times it was recalled
/// correctly, and when it was last recalled correctly.
struct MemoryStat: Codable, Hashable {
    var seen: Int = 0
    var timesRemembered: Int = 0
    var lastRemembered: Date?
}

/// A word paired with the list it belongs to, for practice sessions that may
/// span multiple lists.
struct PracticeCard: Identifiable {
    var word: VocabWord
    let listId: String
    var id: String { word.id ?? UUID().uuidString }
}

/// Daily tally of how many words were remembered per aspect in the daily
/// assignment, stored at users/{uid}/dailyStats/{yyyy-MM-dd}.
struct DailyStat: Codable, Identifiable {
    @DocumentID var id: String?
    var date: String
    var word: Int?
    var translation: Int?
    var pronunciation: Int?
}

/// A single vocabulary entry inside a list.
struct VocabWord: Codable, Identifiable {
    @DocumentID var id: String?
    var term: String
    var translation: String
    var notes: String
    /// Parts of speech (raw values). A word may have several.
    var partsOfSpeech: [String]?
    /// Legacy single part of speech, kept so older documents still decode.
    var partOfSpeech: String?
    /// Optional hiragana reading, used when learning Japanese.
    /// Optional so existing documents without the field still decode.
    var hiragana: String?
    /// Pinyin reading, required when learning Chinese.
    /// Optional on the type so existing documents without the field still decode.
    var pinyin: String?
    /// Firebase Storage path of the pronunciation recording, if any.
    var audioPath: String?
    /// Memory stats per aspect, keyed "translation", "pronunciation", and
    /// "spelling". Optional so older documents still decode. Stored for analysis
    /// only; not shown in the UI.
    var memoryStats: [String: MemoryStat]?
    var createdAt: Date

    // Spaced-repetition tracking (per-aspect; see review-gap schedules below).
    var lastReviewed: Date?
    /// The last time the word was recalled correctly in practice, split by mode.
    /// Optional so older documents (and never-remembered words) decode.
    var lastWordRemembered: Date?
    var lastPronounciationRemembered: Date?
    var lastTranslationRemembered: Date?
    var timesSeen: Int
    /// Correct-recall counts split by practice mode. Optional so older documents
    /// (which only had a single `timesCorrect`) still decode.
    var timesWordCorrect: Int?
    var timesPronounciationCorrect: Int?
    var timesTranslationCorrect: Int?
    /// Whether the word is finally remembered (mastered). Stored in Firebase as
    /// `remember_final`. Optional so older documents still decode.
    var remember_final: Bool?

    init(
        id: String? = nil,
        term: String,
        translation: String,
        notes: String = "",
        partsOfSpeech: [PartOfSpeech] = [],
        hiragana: String? = nil,
        pinyin: String? = nil,
        audioPath: String? = nil,
        memoryStats: [String: MemoryStat]? = nil,
        createdAt: Date = Date(),
        lastReviewed: Date? = nil,
        lastWordRemembered: Date? = nil,
        lastPronounciationRemembered: Date? = nil,
        lastTranslationRemembered: Date? = nil,
        timesSeen: Int = 0,
        timesWordCorrect: Int? = 0,
        timesPronounciationCorrect: Int? = 0,
        timesTranslationCorrect: Int? = 0,
        remember_final: Bool? = false
    ) {
        self.id = id
        self.term = term
        self.translation = translation
        self.notes = notes
        self.partsOfSpeech = partsOfSpeech.map(\.rawValue)
        self.partOfSpeech = nil
        self.hiragana = hiragana
        self.pinyin = pinyin
        self.audioPath = audioPath
        self.memoryStats = memoryStats
        self.createdAt = createdAt
        self.lastReviewed = lastReviewed
        self.lastWordRemembered = lastWordRemembered
        self.lastPronounciationRemembered = lastPronounciationRemembered
        self.lastTranslationRemembered = lastTranslationRemembered
        self.timesSeen = timesSeen
        self.timesWordCorrect = timesWordCorrect
        self.timesPronounciationCorrect = timesPronounciationCorrect
        self.timesTranslationCorrect = timesTranslationCorrect
        self.remember_final = remember_final
    }
}

// MARK: - Leitner spaced-repetition helpers

extension VocabWord {
    /// Non-optional identifier for use as a `ForEach`/selection id.
    var idValue: String { id ?? "" }

    /// The selected parts of speech, reading the new array field and falling
    /// back to the legacy single value. Excludes `.unspecified`.
    var partOfSpeechValues: [PartOfSpeech] {
        if let raw = partsOfSpeech, !raw.isEmpty {
            return raw.compactMap { PartOfSpeech(rawValue: $0) }.filter { $0 != .unspecified }
        }
        if let single = partOfSpeech, let pos = PartOfSpeech(rawValue: single), pos != .unspecified {
            return [pos]
        }
        return []
    }

    /// The phonetic reading to display (hiragana for Japanese, pinyin for
    /// Chinese), if any.
    var reading: String? {
        for value in [hiragana, pinyin] {
            if let value, !value.isEmpty { return value }
        }
        return nil
    }

    /// Whether the word is fully remembered (the `remember_final` flag in
    /// Firebase). Drives the "show remembered only" list filter.
    var isRemembered: Bool { remember_final == true }

    /// Whether the given memory aspect was recalled correctly today.
    func wasRememberedToday(aspect: String) -> Bool {
        guard let last = memoryStats?[aspect]?.lastRemembered else { return false }
        return Calendar.current.isDateInToday(last)
    }

    /// Minimum days between translation reviews, indexed by how many times the
    /// translation has already been remembered. After the 10th it's mastered.
    static let translationReviewGaps = [0, 1, 1, 1, 2, 2, 3, 4, 5, 10]

    /// Whether the translation aspect is due today under the spaced-repetition
    /// schedule: enough days must have passed since it was last remembered.
    func isTranslationDue(now: Date = Date()) -> Bool {
        Self.isDue(count: timesTranslationCorrect ?? 0, last: lastTranslationRemembered,
                   gaps: Self.translationReviewGaps, now: now)
    }

    /// Minimum days between word reviews, indexed by how many times the word has
    /// already been remembered. After the 8th it's mastered.
    static let wordReviewGaps = [0, 1, 1, 2, 3, 4, 6, 9]

    /// Whether the word (spelling) aspect is due today under its schedule.
    func isWordDue(now: Date = Date()) -> Bool {
        Self.isDue(count: timesWordCorrect ?? 0, last: lastWordRemembered,
                   gaps: Self.wordReviewGaps, now: now)
    }

    /// Minimum days between pronunciation reviews, indexed by how many times the
    /// pronunciation has already been remembered. After the 7th it's mastered.
    static let pronunciationReviewGaps = [0, 1, 2, 3, 4, 6, 8]

    /// Whether the pronunciation aspect is due today under its schedule.
    func isPronunciationDue(now: Date = Date()) -> Bool {
        Self.isDue(count: timesPronounciationCorrect ?? 0, last: lastPronounciationRemembered,
                   gaps: Self.pronunciationReviewGaps, now: now)
    }

    /// Shared spaced-repetition due check: due once the required gap of days has
    /// passed since the last remember (or immediately if never remembered), and
    /// not yet mastered (remembered as many times as the schedule has steps).
    private static func isDue(count: Int, last: Date?, gaps: [Int], now: Date) -> Bool {
        guard count < gaps.count else { return false }
        guard let last else { return true }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now)).day ?? 0
        return days >= gaps[count]
    }

    mutating func markCorrect(aspect: String? = nil) {
        let now = Date()
        timesSeen += 1
        // The aspect names map to the practice modes: spelling = Word mode.
        switch aspect {
        case "spelling":
            timesWordCorrect = (timesWordCorrect ?? 0) + 1
            lastWordRemembered = now
        case "pronunciation":
            timesPronounciationCorrect = (timesPronounciationCorrect ?? 0) + 1
            lastPronounciationRemembered = now
        case "translation":
            timesTranslationCorrect = (timesTranslationCorrect ?? 0) + 1
            lastTranslationRemembered = now
        default: break
        }
        updateRememberFinal()
        lastReviewed = now
        record(aspect: aspect, correct: true, now: now)
    }

    mutating func markIncorrect(aspect: String? = nil) {
        timesSeen += 1
        lastReviewed = Date()
        record(aspect: aspect, correct: false, now: Date())
    }

    /// Resets all spaced-repetition progress so the word counts as never
    /// remembered (it will reappear in practice for every aspect).
    mutating func resetMemory() {
        lastReviewed = nil
        lastWordRemembered = nil
        lastPronounciationRemembered = nil
        lastTranslationRemembered = nil
        timesSeen = 0
        timesWordCorrect = 0
        timesPronounciationCorrect = 0
        timesTranslationCorrect = 0
        memoryStats = nil
    }

    /// Marks the word as finally remembered once each mode has enough correct
    /// recalls. Called whenever a per-mode correct count changes.
    private mutating func updateRememberFinal() {
        let word = timesWordCorrect ?? 0
        let translation = timesTranslationCorrect ?? 0
        let pronunciation = timesPronounciationCorrect ?? 0
        // Pronunciation only counts toward mastery for words that have a recording.
        let pronunciationOK = audioPath == nil || pronunciation >= 7
        if word >= 8 && translation >= 10 && pronunciationOK {
            remember_final = true
        }
    }

    /// Updates the memory stats for the aspect tested, if provided.
    private mutating func record(aspect: String?, correct: Bool, now: Date) {
        guard let aspect else { return }
        var stats = memoryStats ?? [:]
        var entry = stats[aspect] ?? MemoryStat()
        entry.seen += 1
        if correct {
            entry.timesRemembered += 1
            entry.lastRemembered = now
        }
        stats[aspect] = entry
        memoryStats = stats
    }
}
