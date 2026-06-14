//
//  AddWordView.swift
//  Retainic
//
//  Create a new word or edit an existing one.
//

import SwiftUI
import SwiftData

struct AddWordView: View {
    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Existing word when editing; nil when creating.
    private let existingWord: Word?

    @State private var term: String
    @State private var translation: String
    @State private var notes: String
    @State private var partOfSpeech: PartOfSpeech

    init(word: Word? = nil) {
        self.existingWord = word
        _term = State(initialValue: word?.term ?? "")
        _translation = State(initialValue: word?.translation ?? "")
        _notes = State(initialValue: word?.notes ?? "")
        _partOfSpeech = State(initialValue: PartOfSpeech(rawValue: word?.partOfSpeech ?? "") ?? .unspecified)
    }

    private var isEditing: Bool { existingWord != nil }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespaces).isEmpty &&
        !translation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section(Language.named(targetLanguage)?.displayName ?? "Word") {
                TextField("Word you're learning", text: $term)
                    .textInputAutocapitalization(.never)
            }

            Section(Language.named(nativeLanguage)?.displayName ?? "Translation") {
                TextField("Translation", text: $translation)
            }

            Section("Part of speech") {
                Picker("Part of speech", selection: $partOfSpeech) {
                    ForEach(PartOfSpeech.allCases) { pos in
                        Text(pos.label(for: nativeLanguage)).tag(pos)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Section("Notes (optional)") {
                TextField("Example sentence or memory hint", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle(isEditing ? "Edit Word" : "New Word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        if let word = existingWord {
            word.term = trimmedTerm
            word.translation = trimmedTranslation
            word.notes = trimmedNotes
            word.partOfSpeech = partOfSpeech.rawValue
        } else {
            let word = Word(term: trimmedTerm, translation: trimmedTranslation, notes: trimmedNotes, partOfSpeech: partOfSpeech)
            modelContext.insert(word)
        }
        dismiss()
    }
}

#Preview {
    AddWordView()
        .modelContainer(for: Word.self, inMemory: true)
}
