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

    /// The language's name written in the given UI language code, e.g. "ja"
    /// renders English as "英語". Falls back to the English `name`.
    func displayName(in uiCode: String) -> String {
        let locale = Locale(identifier: Language.localeIdentifier(for: uiCode))
        guard let localized = locale.localizedString(forLanguageCode: code) else { return name }
        return localized.capitalized(with: locale)
    }

    /// The language's name written in itself (its autonym), e.g. "Español",
    /// "简体中文", "日本語". Falls back to the English `name`.
    var autonym: String {
        let identifier = Language.localeIdentifier(for: code)
        let locale = Locale(identifier: identifier)
        guard let localized = locale.localizedString(forLanguageCode: identifier) else { return name }
        return localized.capitalized(with: locale)
    }

    /// Maps an app language code to a full locale identifier for bundle lookup.
    static func localeIdentifier(for code: String) -> String {
        code == "zh" ? "zh-Hans" : code
    }

    /// The `Locale` for an app language code, used to drive the interface.
    static func locale(for code: String) -> Locale {
        Locale(identifier: localeIdentifier(for: code))
    }

    /// The best supported language for the current device, defaulting to English.
    static var systemDefault: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        return all.contains { $0.code == code } ? code : "en"
    }
}
