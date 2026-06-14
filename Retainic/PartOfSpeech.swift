//
//  PartOfSpeech.swift
//  Retainic
//
//  Grammatical category of a word. Stored as a stable key; displayed
//  with a label localized to the user's native language.
//

import Foundation

enum PartOfSpeech: String, CaseIterable, Identifiable {
    case unspecified
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case preposition
    case conjunction
    case interjection

    var id: String { rawValue }

    /// Localized label, keyed by native-language code (see `Language`).
    /// Falls back to English for unsupported languages.
    func label(for nativeCode: String) -> String {
        let table = PartOfSpeech.labels[nativeCode] ?? PartOfSpeech.labels["en"]!
        return table[self] ?? rawValue.capitalized
    }

    private static let labels: [String: [PartOfSpeech: String]] = [
        "en": [
            .unspecified: "Unspecified",
            .noun: "Noun",
            .verb: "Verb",
            .adjective: "Adjective",
            .adverb: "Adverb",
            .pronoun: "Pronoun",
            .preposition: "Preposition",
            .conjunction: "Conjunction",
            .interjection: "Interjection",
        ],
        "es": [
            .unspecified: "Sin especificar",
            .noun: "Sustantivo",
            .verb: "Verbo",
            .adjective: "Adjetivo",
            .adverb: "Adverbio",
            .pronoun: "Pronombre",
            .preposition: "Preposición",
            .conjunction: "Conjunción",
            .interjection: "Interjección",
        ],
        "zh": [
            .unspecified: "未指定",
            .noun: "名词",
            .verb: "动词",
            .adjective: "形容词",
            .adverb: "副词",
            .pronoun: "代词",
            .preposition: "介词",
            .conjunction: "连词",
            .interjection: "感叹词",
        ],
        "ja": [
            .unspecified: "指定なし",
            .noun: "名詞",
            .verb: "動詞",
            .adjective: "形容詞",
            .adverb: "副詞",
            .pronoun: "代名詞",
            .preposition: "前置詞",
            .conjunction: "接続詞",
            .interjection: "感動詞",
        ],
        "ko": [
            .unspecified: "미지정",
            .noun: "명사",
            .verb: "동사",
            .adjective: "형용사",
            .adverb: "부사",
            .pronoun: "대명사",
            .preposition: "전치사",
            .conjunction: "접속사",
            .interjection: "감탄사",
        ],
    ]
}
