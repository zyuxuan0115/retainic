//
//  NewListSheet.swift
//  Retainic
//
//  Create-list and shared-list import flows.
//

import SwiftUI

struct NewListSheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    let uid: String?
    let onCreate: (_ name: String, _ learningLanguage: String, _ originalLanguage: String) -> Void
    let onImported: () -> Void

    private enum Mode: Hashable { case create, importById }

    @State private var mode: Mode = .create

    // Create
    @State private var name = ""
    @State private var learningLanguage = ""
    @State private var originalLanguage = ""

    // Import — step 1 (look up by ID)
    @State private var importId = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?

    // Import — step 2 (name the copy, then copy the words)
    @State private var pendingImport: SharedList?
    @State private var importName = ""
    @State private var isImporting = false
    @State private var importError: String?

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !learningLanguage.isEmpty
        && !originalLanguage.isEmpty
        && learningLanguage != originalLanguage
    }

    var body: some View {
        NavigationStack {
            if let pending = pendingImport {
                namingView(pending)
            } else {
                formView
            }
        }
    }

    // MARK: - Step 1: create or look up

    private var formView: some View {
        Form {
            Picker("", selection: $mode) {
                Text("Create new").tag(Mode.create)
                Text("Import by ID").tag(Mode.importById)
            }
            .pickerStyle(.segmented)

            if mode == .create {
                createSections
            } else {
                importSection
            }
        }
        .navigationTitle("New List".localized(preferredLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if originalLanguage.isEmpty { originalLanguage = preferredLanguage }
        }
        .toolbar { formToolbar }
    }

    @ViewBuilder private var createSections: some View {
        Section("List name") {
            TextField("e.g. Kitchen vocabulary", text: $name)
        }
        Section {
            Picker("I'm learning", selection: $learningLanguage) {
                Text("Select…").tag("")
                ForEach(Language.all) { language in
                    Text(language.displayName(in: preferredLanguage)).tag(language.code)
                }
            }
            Picker("Translated into", selection: $originalLanguage) {
                Text("Select…").tag("")
                ForEach(Language.all) { language in
                    Text(language.displayName(in: preferredLanguage)).tag(language.code)
                }
            }
        } header: {
            Text("Languages")
        } footer: {
            if learningLanguage != "" && learningLanguage == originalLanguage {
                Text("The two languages must be different.")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var importSection: some View {
        Section {
            TextField("Paste the unique ID", text: $importId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Unique ID")
        } footer: {
            if let lookupError {
                Text(lookupError).foregroundStyle(.red)
            } else {
                Text("Enter the unique ID someone shared with you to add a copy of their wordlist.")
            }
        }
    }

    @ToolbarContentBuilder private var formToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("New List".localized(preferredLanguage)).font(.headline)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(Text("Cancel"))
        }
        ToolbarItem(placement: .confirmationAction) {
            if isLookingUp {
                ProgressView()
            } else if mode == .create {
                Button {
                    onCreate(name, learningLanguage, originalLanguage)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(Text("Create"))
                .disabled(!canCreate)
            } else {
                Button { lookUp() } label: { Image(systemName: "arrow.right") }
                    .accessibilityLabel(Text("Import"))
                    .disabled(importId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Step 2: name the imported copy

    private func namingView(_ shared: SharedList) -> some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Import successful")
                        .font(.title3.bold())
                    Text("Found a wordlist with \(shared.words.count) words. Name your copy below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("List name") {
                TextField("List name", text: $importName)
            }

            if let importError {
                Text(importError).foregroundStyle(.red)
            }
        }
        .navigationTitle("New List".localized(preferredLanguage))
        .navigationBarTitleDisplayMode(.inline)
        // Adding many words must not be interrupted: block swipe-to-dismiss and
        // the back/confirm controls while the copy runs.
        .interactiveDismissDisabled(isImporting)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("New List".localized(preferredLanguage)).font(.headline)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { pendingImport = nil } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("Cancel"))
                    .disabled(isImporting)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isImporting {
                    ProgressView()
                } else {
                    Button { performImport(shared) } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(Text("Add"))
                        .disabled(importName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func lookUp() {
        let id = importId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        isLookingUp = true
        lookupError = nil
        Task {
            do {
                if let shared = try await VocabRepository.fetchSharedList(publicId: id) {
                    importName = shared.list.name
                    pendingImport = shared
                } else {
                    lookupError = "No wordlist found for that ID. Check it and try again."
                        .localized(preferredLanguage)
                }
            } catch {
                lookupError = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    private func performImport(_ shared: SharedList) {
        guard let uid else { return }
        isImporting = true
        importError = nil
        Task {
            do {
                let trimmed = importName.trimmingCharacters(in: .whitespaces)
                let finalName = trimmed.isEmpty ? shared.list.name : trimmed
                let newListId = try await VocabRepository.createList(
                    uid: uid,
                    name: finalName,
                    learningLanguage: shared.list.learningLanguage ?? "",
                    originalLanguage: shared.list.originalLanguage ?? ""
                )
                let words = shared.words.map { source in
                    VocabWord(
                        term: source.term,
                        translation: source.translation,
                        notes: source.notes,
                        partsOfSpeech: source.partOfSpeechValues,
                        hiragana: source.hiragana,
                        pinyin: source.pinyin
                    )
                }
                try await VocabRepository.addWords(uid: uid, listId: newListId, words: words)
                isImporting = false
                onImported()
                dismiss()
            } catch {
                importError = error.localizedDescription
                isImporting = false
            }
        }
    }
}
