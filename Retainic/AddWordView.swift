//
//  AddWordView.swift
//  Retainic
//
//  Create a new word in a list, or edit an existing one. Backed by Firestore.
//

import SwiftUI

struct AddWordView: View {
    let listId: String
    /// Existing word when editing; nil when creating.
    private let existingWord: VocabWord?

    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var term: String
    @State private var translation: String
    @State private var notes: String
    @State private var partOfSpeech: PartOfSpeech
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(listId: String, word: VocabWord? = nil) {
        self.listId = listId
        self.existingWord = word
        _term = State(initialValue: word?.term ?? "")
        _translation = State(initialValue: word?.translation ?? "")
        _notes = State(initialValue: word?.notes ?? "")
        _partOfSpeech = State(initialValue: word?.partOfSpeechValue ?? .unspecified)
    }

    private var isEditing: Bool { existingWord != nil }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespaces).isEmpty &&
        !translation.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSaving
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
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
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard let uid = auth.uid else { return }
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        isSaving = true
        errorMessage = nil

        Task {
            do {
                if var word = existingWord {
                    word.term = trimmedTerm
                    word.translation = trimmedTranslation
                    word.notes = trimmedNotes
                    word.partOfSpeech = partOfSpeech.rawValue
                    try await VocabRepository.updateWord(uid: uid, listId: listId, word: word)
                } else {
                    let word = VocabWord(
                        term: trimmedTerm,
                        translation: trimmedTranslation,
                        notes: trimmedNotes,
                        partOfSpeech: partOfSpeech
                    )
                    try await VocabRepository.addWord(uid: uid, listId: listId, word: word)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
