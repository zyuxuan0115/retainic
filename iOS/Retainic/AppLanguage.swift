//
//  AppLanguage.swift
//  Retainic
//
//  SwiftUI's `\.locale` environment localizes ordinary views, but a few
//  UIKit-bridged surfaces (navigation-bar titles, search prompts) resolve their
//  text against the system language instead. For those, look the string up in a
//  specific language's bundle and pass the resolved value in directly.
//

import Foundation

extension String {
    /// Looks this key up in the given app language's compiled `.lproj`,
    /// returning the key itself if that language isn't available.
    func localized(_ code: String) -> String {
        let identifier = Language.localeIdentifier(for: code)
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return self
        }
        return bundle.localizedString(forKey: self, value: self, table: nil)
    }

    /// Like `localized(_:)` but substitutes a single integer argument into the
    /// resolved format string (e.g. "%lld Selected").
    func localized(_ code: String, _ argument: Int) -> String {
        String(format: localized(code), argument)
    }
}
