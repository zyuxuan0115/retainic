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
    let flag: String

    var id: String { code }

    static let all: [Language] = [
        Language(code: "en", name: "English", flag: "🇬🇧"),
        Language(code: "es", name: "Spanish", flag: "🇪🇸"),
        Language(code: "zh", name: "Chinese", flag: "🇨🇳"),
        Language(code: "ja", name: "Japanese", flag: "🇯🇵"),
        Language(code: "ko", name: "Korean", flag: "🇰🇷"),
    ]

    static func named(_ code: String) -> Language? {
        all.first { $0.code == code }
    }

    var displayName: String { "\(flag) \(name)" }
}
