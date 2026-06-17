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

/// A word paired with the list it belongs to, for practice sessions that may
/// span multiple lists.
struct PracticeCard: Identifiable {
    var word: VocabWord
    let listId: String
    var id: String { word.id ?? UUID().uuidString }
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
    var createdAt: Date

    // Spaced-repetition tracking (Leitner system).
    var box: Int
    var lastReviewed: Date?
    var timesSeen: Int
    var timesCorrect: Int

    init(
        id: String? = nil,
        term: String,
        translation: String,
        notes: String = "",
        partsOfSpeech: [PartOfSpeech] = [],
        hiragana: String? = nil,
        pinyin: String? = nil,
        audioPath: String? = nil,
        createdAt: Date = Date(),
        box: Int = 1,
        lastReviewed: Date? = nil,
        timesSeen: Int = 0,
        timesCorrect: Int = 0
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
        self.createdAt = createdAt
        self.box = box
        self.lastReviewed = lastReviewed
        self.timesSeen = timesSeen
        self.timesCorrect = timesCorrect
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

    /// Whether this card is due for review based on its Leitner box.
    var isDue: Bool {
        guard let lastReviewed else { return true }
        return Date() >= lastReviewed.addingTimeInterval(Self.reviewInterval(forBox: box))
    }

    /// Seconds between reviews for each box level.
    static func reviewInterval(forBox box: Int) -> TimeInterval {
        let days: Double
        switch box {
        case 1: days = 0
        case 2: days = 1
        case 3: days = 3
        case 4: days = 7
        default: days = 16
        }
        return days * 24 * 60 * 60
    }

    mutating func markCorrect() {
        timesSeen += 1
        timesCorrect += 1
        box = min(box + 1, 5)
        lastReviewed = Date()
    }

    mutating func markIncorrect() {
        timesSeen += 1
        box = 1
        lastReviewed = Date()
    }
}
