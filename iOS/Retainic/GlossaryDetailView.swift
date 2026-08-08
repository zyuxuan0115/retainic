//
//  GlossaryDetailView.swift
//  Retainic
//
//  Terms inside a glossary, plus the glossary's own settings.
//

import SwiftUI
import Combine

@MainActor
final class GlossaryEntriesViewModel: ObservableObject {
    @Published var entries: [GlossaryEntry] = []
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var errorMessage: String?

    func load(uid: String, glossaryId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await GlossaryRepository.fetchEntries(uid: uid, glossaryId: glossaryId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(uid: String, glossaryId: String, entry: GlossaryEntry) async {
        guard let id = entry.id else { return }
        do {
            try await GlossaryRepository.deleteEntry(uid: uid, glossaryId: glossaryId, entryId: id)
            entries.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(uid: String, glossaryId: String, to name: String) async {
        do {
            try await GlossaryRepository.renameGlossary(uid: uid, glossaryId: glossaryId, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resets every entry's progress so the whole glossary counts as not
    /// remembered.
    func resetAllMemory(uid: String, glossaryId: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            var updated = entries
            for i in updated.indices {
                updated[i].resetMemory()
                try await GlossaryRepository.updateEntry(uid: uid, glossaryId: glossaryId, entry: updated[i])
            }
            entries = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GlossaryDetailView: View {
    let glossary: Glossary

    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = GlossaryEntriesViewModel()

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @State private var glossaryName: String
    @State private var showingAdd = false
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showingSettings = false
    @State private var entryFilter: WordFilter = .all
    @State private var pendingDeleteEntries: [GlossaryEntry] = []
    @State private var pendingDeleteIsSelection = false
    @State private var showingDeleteConfirm = false

    init(glossary: Glossary) {
        self.glossary = glossary
        _glossaryName = State(initialValue: glossary.name)
    }

    private var glossaryId: String { glossary.id ?? "" }
    private var isSelecting: Bool { editMode == .active }

    private var practiceCards: [GlossaryPracticeCard] {
        vm.entries.map { GlossaryPracticeCard(entry: $0, glossaryId: glossaryId) }
    }

    private var filteredEntries: [GlossaryEntry] {
        var result = vm.entries
        switch entryFilter {
        case .all: break
        case .remembered: result = result.filter(\.isRemembered)
        case .unremembered: result = result.filter { !$0.isRemembered }
        }
        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.term.localizedCaseInsensitiveContains(searchText) ||
                entry.definitionTexts.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.entries.isEmpty {
                ProgressView("Loading…")
            } else if vm.entries.isEmpty {
                emptyState
            } else {
                entriesList
            }
        }
        .navigationTitle(isSelecting ? selectionTitle : glossaryName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .environment(\.editMode, $editMode)
        .toolbar { toolbarContent }
        // Hide the app tab bar here so its bottom is free for this screen's own
        // toolbar, exactly as the word list does.
        .toolbar(.hidden, for: .tabBar)
        .task(id: auth.uid) {
            if let uid = auth.uid { await vm.load(uid: uid, glossaryId: glossaryId) }
        }
        .refreshable {
            if let uid = auth.uid { await vm.load(uid: uid, glossaryId: glossaryId) }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            NavigationStack {
                AddEntryView(glossaryId: glossaryId, language: glossary.language ?? "")
            }
            .preferredLocale(preferredLanguage)
        }
        .sheet(isPresented: $showingSettings) {
            GlossarySettingsSheet(
                name: glossaryName,
                filter: $entryFilter,
                onSave: { renameGlossary(to: $0) },
                onResetMemory: { resetMemory() }
            )
            .preferredLocale(preferredLanguage)
        }
        .repositoryErrorAlert($vm.errorMessage, language: preferredLanguage)
        .alert(
            deletePrompt(count: pendingDeleteEntries.count),
            isPresented: $showingDeleteConfirm
        ) {
            Button("Cancel".localized(preferredLanguage), role: .cancel) { cancelDelete() }
            Button("Delete".localized(preferredLanguage), role: .destructive) { confirmDelete() }
        }
    }

    private func deletePrompt(count: Int) -> String {
        count == 1
            ? "Delete this term?".localized(preferredLanguage)
            : "Delete %lld terms?".localized(preferredLanguage, count)
    }

    private var selectionTitle: String {
        selection.isEmpty
            ? "Select Terms".localized(preferredLanguage)
            : "%lld Selected".localized(preferredLanguage, selection.count)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    endSelection()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(Text("Done"))
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()

                Button(role: .destructive) {
                    pendingDeleteEntries = vm.entries.filter { selection.contains($0.id ?? "") }
                    pendingDeleteIsSelection = true
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty || vm.isBusy)
            }
        } else {
            if !vm.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        beginSelection()
                    } label: {
                        Label("Select", systemImage: "checklist")
                    }
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if !vm.entries.isEmpty {
                    NavigationLink {
                        GlossaryFlashcardView(cards: practiceCards)
                    } label: {
                        Label("Practice", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Term", systemImage: "plus")
                }
            }
        }
    }

    private var entriesList: some View {
        List(selection: $selection) {
            ForEach(filteredEntries, id: \.idValue) { entry in
                NavigationLink {
                    AddEntryView(glossaryId: glossaryId, language: glossary.language ?? "", entry: entry, onDelete: reload)
                } label: {
                    GlossaryEntryRow(entry: entry)
                }
            }
            .onDelete(perform: deleteEntries)
        }
        .searchable(text: $searchText, prompt: "Search terms".localized(preferredLanguage))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Terms Yet", systemImage: "character.book.closed")
        } description: {
            Text("Add the terms you want to remember to “\(glossaryName)”.")
        } actions: {
            Button("Add Your First Term") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func reload() {
        guard let uid = auth.uid else { return }
        Task { await vm.load(uid: uid, glossaryId: glossaryId) }
    }

    private func deleteEntries(at offsets: IndexSet) {
        // Confirm before removing: stash the entries and ask the user first.
        pendingDeleteEntries = offsets.map { filteredEntries[$0] }
        pendingDeleteIsSelection = false
        showingDeleteConfirm = true
    }

    private func cancelDelete() {
        pendingDeleteEntries = []
        pendingDeleteIsSelection = false
    }

    private func confirmDelete() {
        guard let uid = auth.uid else { cancelDelete(); return }
        let toDelete = pendingDeleteEntries
        let wasSelection = pendingDeleteIsSelection
        Task {
            for entry in toDelete { await vm.delete(uid: uid, glossaryId: glossaryId, entry: entry) }
            if wasSelection { endSelection() }
        }
        pendingDeleteEntries = []
        pendingDeleteIsSelection = false
    }

    private func renameGlossary(to name: String) {
        guard let uid = auth.uid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        glossaryName = trimmed
        Task { await vm.rename(uid: uid, glossaryId: glossaryId, to: trimmed) }
    }

    private func resetMemory() {
        guard let uid = auth.uid else { return }
        Task { await vm.resetAllMemory(uid: uid, glossaryId: glossaryId) }
    }

    private func beginSelection() {
        selection.removeAll()
        withAnimation { editMode = .active }
    }

    private func endSelection() {
        selection.removeAll()
        withAnimation { editMode = .inactive }
    }
}

/// One term and its definition in the glossary list.
struct GlossaryEntryRow: View {
    let entry: GlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.term)
                .font(.headline)
            Text(entry.joinedDefinitions)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// Per-glossary settings: rename it and reset every term's remembered state.
struct GlossarySettingsSheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @Binding private var filter: WordFilter
    @State private var showingResetConfirm = false
    private let originalName: String
    let onSave: (String) -> Void
    let onResetMemory: () -> Void

    init(name: String, filter: Binding<WordFilter>, onSave: @escaping (String) -> Void, onResetMemory: @escaping () -> Void) {
        _name = State(initialValue: name)
        _filter = filter
        self.originalName = name
        self.onSave = onSave
        self.onResetMemory = onResetMemory
    }

    /// Save is enabled only once the name is non-empty and actually differs from
    /// the glossary's current name — nothing to save otherwise.
    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != originalName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Glossary name") {
                    TextField("Glossary name", text: $name)
                }

                Section("Show terms") {
                    Picker("Show terms", selection: $filter) {
                        ForEach(WordFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Mark all as not remembered", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Every term in this glossary will show up again in practice.")
                }
            }
            .navigationTitle("Glossary Settings".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Glossary Settings".localized(preferredLanguage)).font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(name)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("Save"))
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Mark all terms as not remembered?".localized(preferredLanguage),
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark All as Not Remembered".localized(preferredLanguage), role: .destructive) {
                    onResetMemory()
                    dismiss()
                }
                Button("Cancel".localized(preferredLanguage), role: .cancel) {}
            }
        }
    }
}
