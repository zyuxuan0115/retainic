//
//  SettingsView.swift
//  Retainic
//
//  Change languages and view progress.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""
    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""

    @Query private var words: [Word]

    var body: some View {
        NavigationStack {
            Form {
                Section("Languages") {
                    Picker("I speak", selection: $nativeLanguage) {
                        ForEach(Language.all) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }
                    Picker("I'm learning", selection: $targetLanguage) {
                        ForEach(Language.all) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }
                }

                Section("Progress") {
                    LabeledContent("Total words", value: "\(words.count)")
                    LabeledContent("Due for review", value: "\(words.filter(\.isDue).count)")
                    LabeledContent("Mastered", value: "\(words.filter { $0.box >= 5 }.count)")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: Word.self, inMemory: true)
}
