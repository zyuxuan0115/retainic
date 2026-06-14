//
//  Word.swift
//  Retainic
//
//  A vocabulary entry the user is learning.
//

import Foundation
import SwiftData

@Model
final class Word {
    /// The word in the language being learned.
    var term: String
    /// The meaning in the user's native language.
    var translation: String
    /// Optional context, example sentence, or memory hint.
    var notes: String
    /// Grammatical category, stored as a `PartOfSpeech` raw value.
    var partOfSpeech: String = PartOfSpeech.unspecified.rawValue
    var createdAt: Date

    // MARK: Spaced-repetition tracking (Leitner system)

    /// Leitner box, 1...5. Higher boxes are reviewed less often.
    var box: Int
    var lastReviewed: Date?
    var timesSeen: Int
    var timesCorrect: Int

    init(term: String, translation: String, notes: String = "", partOfSpeech: PartOfSpeech = .unspecified) {
        self.term = term
        self.translation = translation
        self.notes = notes
        self.partOfSpeech = partOfSpeech.rawValue
        self.createdAt = Date()
        self.box = 1
        self.lastReviewed = nil
        self.timesSeen = 0
        self.timesCorrect = 0
    }

    /// Whether this card is due for review based on its Leitner box.
    var isDue: Bool {
        guard let lastReviewed else { return true }
        let interval = Word.reviewInterval(forBox: box)
        return Date() >= lastReviewed.addingTimeInterval(interval)
    }

    /// Days between reviews for each box level.
    static func reviewInterval(forBox box: Int) -> TimeInterval {
        let days: Double
        switch box {
        case 1: days = 0          // same day
        case 2: days = 1
        case 3: days = 3
        case 4: days = 7
        default: days = 16
        }
        return days * 24 * 60 * 60
    }

    func markCorrect() {
        timesSeen += 1
        timesCorrect += 1
        box = min(box + 1, 5)
        lastReviewed = Date()
    }

    func markIncorrect() {
        timesSeen += 1
        box = 1
        lastReviewed = Date()
    }
}
