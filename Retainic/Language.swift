//
//  Language.swift
//  Retainic
//
//  A curated set of languages the user can choose from.
//

import Foundation

struct Language: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    static let all: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
    ]

    static func named(_ code: String) -> Language? {
        all.first { $0.code == code }
    }

    var displayName: String { name }
}
