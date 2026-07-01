//
//  AboutView.swift
//  Retainic
//
//  App description and source-code link. Mirrors the web app's About page.
//

import SwiftUI

struct AboutView: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    private static let repoURL = URL(string: "https://github.com/zyuxuan0115/retainic")!

    /// Marketing version from the bundle (e.g. "1.0"), falling back if absent.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text(verbatim: "Retainic")
                        .font(.title.bold())
                    Text("Vocabulary learning with spaced-repetition flashcards.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("About") {
                Text("Retainic lets you build vocabulary lists, add words with translations, readings, parts of speech and recorded pronunciation, then practice them with per-aspect spaced repetition. This iOS app shares the same account and data as the Retainic web app.")
                    .font(.subheadline)
            }

            Section("Source code") {
                Link(destination: Self.repoURL) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text(verbatim: "github.com/zyuxuan0115/retainic")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text(verbatim: "© 2026 Retainic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("About".localized(preferredLanguage))
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
