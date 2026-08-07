//
//  GlossaryModels.swift
//  Retainic
//
//  A glossary is a single-language reference deck: each entry is a term and its
//  definition. Glossaries are independent of vocabulary lists — their own
//  documents, screens and practice — but they run on the same spaced-repetition
//  schedule (see ReviewSchedule), with two methods instead of three: recalling
//  the term and recalling the definition. There is no audio and no translation
//  language, so the pronunciation method never applies.
//
//  Layout:
//    users/{uid}/glossaries/{glossaryId}                    -> Glossary
//    users/{uid}/glossaries/{glossaryId}/entries/{entryId}  -> GlossaryEntry
//

import Foundation
import SwiftUI
import FirebaseFirestore

/// A named glossary (reference deck) owned by a user.
struct Glossary: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date
    var entryCount: Int
    /// The one language its terms and definitions are written in. Optional so
    /// older documents still decode.
    var language: String?
    /// When the glossary was moved to the trash, or nil if it's active.
    var deletedAt: Date?

    init(
        id: String? = nil,
        name: String,
        createdAt: Date,
        entryCount: Int,
        language: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.entryCount = entryCount
        self.language = language
        self.deletedAt = deletedAt
    }
}

/// The two things a glossary entry is practised on.
enum GlossaryAspect: String, CaseIterable, Identifiable {
    case term, definition

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .term: return "Term"
        case .definition: return "Definition"
        }
    }

    /// The word aspect this method shares its daily tally with, so glossary
    /// practice shows up in Statistics alongside list practice.
    var dailyAspect: String {
        switch self {
        case .term: return "spelling"
        case .definition: return "translation"
        }
    }
}

/// A single term inside a glossary.
struct GlossaryEntry: Codable, Identifiable {
    @DocumentID var id: String?
    var term: String
    var definition: String
    var notes: String
    /// Memory stats per aspect, keyed "term" and "definition". Stored for
    /// analysis only; not shown in the UI.
    var memoryStats: [String: MemoryStat]?
    var createdAt: Date

    // Spaced-repetition tracking, one method per side of the entry.
    var lastReviewed: Date?
    var lastTermRemembered: Date?
    var lastDefinitionRemembered: Date?
    var timesSeen: Int
    var timesTermCorrect: Int?
    var timesDefinitionCorrect: Int?
    /// Whether the entry is finally remembered (mastered). Stored in Firebase as
    /// `remember_final`, matching the word documents.
    var remember_final: Bool?

    init(
        id: String? = nil,
        term: String,
        definition: String,
        notes: String = "",
        memoryStats: [String: MemoryStat]? = nil,
        createdAt: Date = Date(),
        lastReviewed: Date? = nil,
        lastTermRemembered: Date? = nil,
        lastDefinitionRemembered: Date? = nil,
        timesSeen: Int = 0,
        timesTermCorrect: Int? = 0,
        timesDefinitionCorrect: Int? = 0,
        remember_final: Bool? = false
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.notes = notes
        self.memoryStats = memoryStats
        self.createdAt = createdAt
        self.lastReviewed = lastReviewed
        self.lastTermRemembered = lastTermRemembered
        self.lastDefinitionRemembered = lastDefinitionRemembered
        self.timesSeen = timesSeen
        self.timesTermCorrect = timesTermCorrect
        self.timesDefinitionCorrect = timesDefinitionCorrect
        self.remember_final = remember_final
    }
}

/// An entry paired with the glossary it belongs to, for practice sessions.
struct GlossaryPracticeCard: Identifiable {
    var entry: GlossaryEntry
    let glossaryId: String
    var id: String { entry.id ?? UUID().uuidString }
}

// MARK: - Spaced repetition

extension GlossaryEntry {
    /// Non-optional identifier for use as a `ForEach`/selection id.
    var idValue: String { id ?? "" }

    /// Whether the entry is fully remembered. Drives the "show remembered only"
    /// filter, exactly as it does for words.
    var isRemembered: Bool { remember_final == true }

    /// The term side follows the word (spelling) schedule, the definition side
    /// the translation schedule — the same gaps a word is reviewed on.
    static let termReviewGaps = VocabWord.wordReviewGaps
    static let definitionReviewGaps = VocabWord.translationReviewGaps

    func isTermDue(now: Date = Date()) -> Bool {
        ReviewSchedule.isDue(count: timesTermCorrect ?? 0, last: lastTermRemembered,
                             gaps: Self.termReviewGaps, now: now)
    }

    func isDefinitionDue(now: Date = Date()) -> Bool {
        ReviewSchedule.isDue(count: timesDefinitionCorrect ?? 0, last: lastDefinitionRemembered,
                             gaps: Self.definitionReviewGaps, now: now)
    }

    func isDue(_ aspect: GlossaryAspect, now: Date = Date()) -> Bool {
        switch aspect {
        case .term: return isTermDue(now: now)
        case .definition: return isDefinitionDue(now: now)
        }
    }

    /// Records a correct recall for the given method.
    mutating func markCorrect(aspect: GlossaryAspect) {
        let now = Date()
        timesSeen += 1
        switch aspect {
        case .term:
            timesTermCorrect = (timesTermCorrect ?? 0) + 1
            lastTermRemembered = now
        case .definition:
            timesDefinitionCorrect = (timesDefinitionCorrect ?? 0) + 1
            lastDefinitionRemembered = now
        }
        updateRememberFinal()
        lastReviewed = now
        record(aspect: aspect, correct: true, now: now)
    }

    mutating func markIncorrect(aspect: GlossaryAspect) {
        let now = Date()
        timesSeen += 1
        lastReviewed = now
        record(aspect: aspect, correct: false, now: now)
    }

    /// Resets all review progress so the entry counts as never remembered.
    mutating func resetMemory() {
        lastReviewed = nil
        lastTermRemembered = nil
        lastDefinitionRemembered = nil
        timesSeen = 0
        timesTermCorrect = 0
        timesDefinitionCorrect = 0
        memoryStats = nil
        remember_final = false
    }

    /// An entry is memorized once both methods have run their schedules out:
    /// 8× term and 10× definition. Entries carry no audio, so the pronunciation
    /// requirement words can have never applies here.
    private mutating func updateRememberFinal() {
        remember_final = (timesTermCorrect ?? 0) >= Self.termReviewGaps.count
            && (timesDefinitionCorrect ?? 0) >= Self.definitionReviewGaps.count
    }

    private mutating func record(aspect: GlossaryAspect, correct: Bool, now: Date) {
        var stats = memoryStats ?? [:]
        var stat = stats[aspect.rawValue] ?? MemoryStat()
        stat.seen += 1
        if correct {
            stat.timesRemembered += 1
            stat.lastRemembered = now
        }
        stats[aspect.rawValue] = stat
        memoryStats = stats
    }
}
