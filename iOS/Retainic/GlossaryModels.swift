//
//  GlossaryModels.swift
//  Retainic
//
//  A glossary is a single-language reference deck: each entry is a term and its
//  definitions. Glossaries are independent of vocabulary lists — their own
//  documents, screens and practice — but they run on the same spaced-repetition
//  schedule (see ReviewSchedule), with two methods instead of three: recalling
//  the term and recalling the definition. There is no audio and no translation
//  language, so the pronunciation method never applies.
//
//  A term can mean several things, so an entry carries a list of definitions,
//  each with its own schedule: shown a definition, you recall the term, and
//  every definition is a card of its own. The other direction — shown the term,
//  recall what it means — stays one card that reveals them all.
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

    var label: LocalizedStringKey {
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

/// One of the things a term means, with the review progress of its own card.
struct GlossaryDefinition: Codable, Hashable {
    var text: String = ""
    var timesCorrect: Int = 0
    var lastRemembered: Date?
}

/// A single term inside a glossary.
struct GlossaryEntry: Codable, Identifiable {
    @DocumentID var id: String?
    var term: String
    /// Everything the term means, each definition scheduled separately. Empty
    /// on entries written before a term could mean several things, which store
    /// the one meaning in `definition` instead.
    var definitions: [GlossaryDefinition]?
    /// The definitions as one line. Kept in step with `definitions` so clients
    /// that only know about a single definition still read something coherent.
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
        definitions: [String],
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
        self.definitions = definitions.map { GlossaryDefinition(text: $0) }
        self.definition = definitions.joined(separator: "; ")
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

    /// The entry's definitions, each with its own schedule. An entry written
    /// before a term could mean several things reads as a single definition
    /// carrying the entry's definition counters.
    var definitionList: [GlossaryDefinition] {
        if let definitions, !definitions.isEmpty { return definitions }
        guard !definition.isEmpty else { return [] }
        return [GlossaryDefinition(text: definition,
                                   timesCorrect: timesDefinitionCorrect ?? 0,
                                   lastRemembered: lastDefinitionRemembered)]
    }

    /// Just the text of each definition, for display and search.
    var definitionTexts: [String] { definitionList.map(\.text) }

    /// The definitions as one line, for list rows and the legacy single field.
    var joinedDefinitions: String { definitionTexts.joined(separator: "; ") }

    func isTermDue(now: Date = Date()) -> Bool {
        ReviewSchedule.isDue(count: timesTermCorrect ?? 0, last: lastTermRemembered,
                             gaps: Self.termReviewGaps, now: now)
    }

    /// Whether a definition is due. With no `index`, whether any is.
    func isDefinitionDue(at index: Int? = nil, now: Date = Date()) -> Bool {
        let list = definitionList
        func due(_ i: Int) -> Bool {
            ReviewSchedule.isDue(count: list[i].timesCorrect, last: list[i].lastRemembered,
                                 gaps: Self.definitionReviewGaps, now: now)
        }
        if let index { return list.indices.contains(index) ? due(index) : false }
        return list.indices.contains { due($0) }
    }

    /// The positions of the definitions due for review right now.
    func dueDefinitionIndexes(now: Date = Date()) -> [Int] {
        definitionList.indices.filter { isDefinitionDue(at: $0, now: now) }
    }

    func isDue(_ aspect: GlossaryAspect, definitionIndex: Int? = nil, now: Date = Date()) -> Bool {
        switch aspect {
        case .term: return isTermDue(now: now)
        case .definition: return isDefinitionDue(at: definitionIndex, now: now)
        }
    }

    /// Records a correct recall for the given method. A definition recall
    /// advances only the definition that was practised.
    mutating func markCorrect(aspect: GlossaryAspect, definitionIndex: Int = 0) {
        let now = Date()
        timesSeen += 1
        switch aspect {
        case .term:
            timesTermCorrect = (timesTermCorrect ?? 0) + 1
            lastTermRemembered = now
        case .definition:
            var list = definitionList
            if list.indices.contains(definitionIndex) {
                list[definitionIndex].timesCorrect += 1
                list[definitionIndex].lastRemembered = now
            }
            definitions = list
            syncDefinitionFields()
        }
        updateRememberFinal()
        lastReviewed = now
        record(aspect: aspect, correct: true, now: now)
    }

    /// Replaces the entry's definitions with `texts`, keeping the review
    /// progress at each position: editing the wording of a definition leaves
    /// its schedule alone, a new one starts unlearned, and a removed one takes
    /// its progress with it.
    mutating func setDefinitions(_ texts: [String]) {
        let previous = definitionList
        definitions = texts.enumerated().map { index, text in
            GlossaryDefinition(text: text,
                               timesCorrect: previous.indices.contains(index) ? previous[index].timesCorrect : 0,
                               lastRemembered: previous.indices.contains(index) ? previous[index].lastRemembered : nil)
        }
        syncDefinitionFields()
        updateRememberFinal()
    }

    /// Mirrors the definition list onto the fields that predate it: the joined
    /// text, the lowest per-definition count (what mastery waits on), and the
    /// most recent recall (what Statistics counts).
    private mutating func syncDefinitionFields() {
        let list = definitionList
        definition = list.map(\.text).joined(separator: "; ")
        timesDefinitionCorrect = list.map(\.timesCorrect).min() ?? 0
        lastDefinitionRemembered = list.compactMap(\.lastRemembered).max()
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
        definitions = definitionTexts.map { GlossaryDefinition(text: $0) }
        memoryStats = nil
        remember_final = false
    }

    /// An entry is memorized once both methods have run their schedules out:
    /// 8× term and 10× for every definition — a term with five meanings isn't
    /// done until all five are. Entries carry no audio, so the pronunciation
    /// requirement words can have never applies here.
    private mutating func updateRememberFinal() {
        let definitionsFinished = definitionList.allSatisfy { $0.timesCorrect >= Self.definitionReviewGaps.count }
        remember_final = (timesTermCorrect ?? 0) >= Self.termReviewGaps.count
            && !definitionList.isEmpty && definitionsFinished
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
