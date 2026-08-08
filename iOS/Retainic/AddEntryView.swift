//
//  AddEntryView.swift
//  Retainic
//
//  Create a new term in a glossary, or edit an existing one. Backed by
//  Firestore.
//

import SwiftUI

struct AddEntryView: View {
    let glossaryId: String
    /// The glossary's language, used to title the term field.
    let language: String
    /// Existing entry when editing; nil when creating.
    private let existingEntry: GlossaryEntry?
    /// Called after the entry is deleted, so the presenter can refresh its list.
    private let onDelete: (() -> Void)?

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var term: String
    /// One field per definition — a term can mean several things, and each
    /// meaning is practised on its own.
    @State private var definitions: [String]
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirm = false

    init(glossaryId: String, language: String, entry: GlossaryEntry? = nil, onDelete: (() -> Void)? = nil) {
        self.glossaryId = glossaryId
        self.language = language
        self.existingEntry = entry
        self.onDelete = onDelete
        _term = State(initialValue: entry?.term ?? "")
        let saved = entry?.definitionTexts ?? []
        _definitions = State(initialValue: saved.isEmpty ? [""] : saved)
        _notes = State(initialValue: entry?.notes ?? "")
    }

    private var isEditing: Bool { existingEntry != nil }

    /// The definitions that would be saved: trimmed, with the blank fields
    /// dropped.
    private var filledDefinitions: [String] {
        definitions.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty,
              !filledDefinitions.isEmpty,
              !isSaving else { return false }
        // When editing, Save stays disabled until something actually changes.
        return hasChanges
    }

    /// Whether the form differs from the entry being edited. Always true when
    /// creating (there's nothing to compare against).
    private var hasChanges: Bool {
        guard let entry = existingEntry else { return true }
        if term.trimmingCharacters(in: .whitespaces) != entry.term { return true }
        if filledDefinitions != entry.definitionTexts { return true }
        if notes.trimmingCharacters(in: .whitespaces) != entry.notes { return true }
        return false
    }

    var body: some View {
        Form {
            Section(Language.named(language)?.displayName(in: preferredLanguage)
                    ?? String(localized: "Term", locale: Language.locale(for: preferredLanguage))) {
                TextField("Term", text: $term)
                    .textInputAutocapitalization(.never)
            }

            Section("Definitions") {
                ForEach(definitions.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        TextField("What it means", text: $definitions[index], axis: .vertical)
                            .lineLimit(1...5)
                        // The last remaining field stays: an entry always has
                        // a definition.
                        if definitions.count > 1 {
                            Button {
                                definitions.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove definition"))
                        }
                    }
                }
                Button {
                    definitions.append("")
                } label: {
                    Label("Add definition", systemImage: "plus.circle")
                }
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

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Term", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isSaving)
                }
            }
        }
        .navigationTitle((isEditing ? "Edit Term" : "New Term").localized(preferredLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Term".localized(preferredLanguage), isPresented: $showingDeleteConfirm) {
            Button("Delete".localized(preferredLanguage), role: .destructive) { deleteEntry() }
            Button("Cancel".localized(preferredLanguage), role: .cancel) {}
        } message: {
            Text("This term will be permanently deleted.")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text((isEditing ? "Edit Term" : "New Term").localized(preferredLanguage)).font(.headline)
            }
            if !isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancel"))
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(Text("Save"))
                .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard let uid = auth.uid else { return }
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        let trimmedDefinitions = filledDefinitions
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        isSaving = true
        errorMessage = nil

        Task {
            do {
                if var entry = existingEntry {
                    entry.term = trimmedTerm
                    entry.setDefinitions(trimmedDefinitions)
                    entry.notes = trimmedNotes
                    try await GlossaryRepository.updateEntry(uid: uid, glossaryId: glossaryId, entry: entry)
                } else {
                    let entry = GlossaryEntry(
                        term: trimmedTerm,
                        definitions: trimmedDefinitions,
                        notes: trimmedNotes
                    )
                    try await GlossaryRepository.addEntry(uid: uid, glossaryId: glossaryId, entry: entry)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func deleteEntry() {
        guard let uid = auth.uid, let entryId = existingEntry?.id else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await GlossaryRepository.deleteEntry(uid: uid, glossaryId: glossaryId, entryId: entryId)
                onDelete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
