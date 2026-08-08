//
//  ListDetailView.swift
//  Retainic
//
//  Words inside a vocabulary list and the interactions that coordinate them.
//

import SwiftUI

struct ListDetailView: View {
    let list: VocabularyList

    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = WordsViewModel()

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @State private var listName: String
    /// Per-list text-to-speech fallback, seeded from the list and kept in sync as
    /// the user toggles it in List Settings.
    @State private var ttsEnabled: Bool
    @State private var showingAdd = false
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showingMoveSheet = false
    @State private var showingListSettings = false
    @State private var wordFilter: WordFilter = .all
    @State private var pendingDeleteWords: [VocabWord] = []
    @State private var pendingDeleteIsSelection = false
    @State private var showingDeleteConfirm = false

    init(list: VocabularyList) {
        self.list = list
        _listName = State(initialValue: list.name)
        _ttsEnabled = State(initialValue: list.ttsEnabled ?? false)
    }

    private var listId: String { list.id ?? "" }
    private var learningLanguage: String { list.learningLanguage ?? "" }
    private var originalLanguage: String { list.originalLanguage ?? "" }
    private var isSelecting: Bool { editMode == .active }

    private var practiceCards: [PracticeCard] {
        vm.words.map { PracticeCard(word: $0, listId: listId) }
    }

    private var filteredWords: [VocabWord] {
        var result = vm.words
        switch wordFilter {
        case .all: break
        case .remembered: result = result.filter(\.isRemembered)
        case .unremembered: result = result.filter { !$0.isRemembered }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.term.localizedCaseInsensitiveContains(searchText) ||
                $0.translation.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.words.isEmpty {
                ProgressView("Loading…")
            } else if vm.words.isEmpty {
                emptyState
            } else {
                wordsList
            }
        }
        .navigationTitle(isSelecting ? selectionTitle : listName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .environment(\.editMode, $editMode)
        .toolbar { toolbarContent }
        // Hide the app tab bar on this screen so its bottom is free for the
        // list's own toolbar (the Settings gear, and Move/Delete while selecting)
        // — otherwise the tab bar's Settings tab covers them.
        .toolbar(.hidden, for: .tabBar)
        .task(id: auth.uid) {
            if let uid = auth.uid { await vm.load(uid: uid, listId: listId) }
        }
        .refreshable {
            if let uid = auth.uid { await vm.load(uid: uid, listId: listId) }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            NavigationStack {
                AddWordView(listId: listId, learningLanguage: learningLanguage, originalLanguage: originalLanguage, ttsEnabled: ttsEnabled)
            }
            .preferredLocale(preferredLanguage)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveDestinationSheet(
                targets: vm.moveTargets,
                count: selection.count
            ) { destination in
                moveSelected(to: destination)
            }
            .preferredLocale(preferredLanguage)
        }
        .sheet(isPresented: $showingListSettings) {
            ListSettingsSheet(
                name: listName,
                filter: $wordFilter,
                ttsEnabled: ttsEnabled,
                publicId: list.publicId,
                onSave: { renameList(to: $0) },
                onSetTTS: { setTTS($0) },
                onResetMemory: { resetMemory() }
            )
            .preferredLocale(preferredLanguage)
        }
        .repositoryErrorAlert($vm.errorMessage, language: preferredLanguage)
        .alert(
            deletePrompt(count: pendingDeleteWords.count),
            isPresented: $showingDeleteConfirm
        ) {
            Button("Cancel".localized(preferredLanguage), role: .cancel) { cancelDelete() }
            Button("Delete".localized(preferredLanguage), role: .destructive) { confirmDelete() }
        }
    }

    private func deletePrompt(count: Int) -> String {
        count == 1
            ? "Delete this word?".localized(preferredLanguage)
            : "Delete %lld words?".localized(preferredLanguage, count)
    }

    private var selectionTitle: String {
        selection.isEmpty
            ? "Select Words".localized(preferredLanguage)
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
                Button {
                    beginMove()
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .disabled(selection.isEmpty || vm.isBusy)

                Spacer()

                Button(role: .destructive) {
                    pendingDeleteWords = vm.words.filter { selection.contains($0.id ?? "") }
                    pendingDeleteIsSelection = true
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty || vm.isBusy)
            }
        } else {
            if !vm.words.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        beginSelection()
                    } label: {
                        Label("Select", systemImage: "checklist")
                    }
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if !vm.words.isEmpty {
                    NavigationLink {
                        FlashcardView(cards: practiceCards, learningLanguage: learningLanguage, ttsEnabled: ttsEnabled)
                    } label: {
                        Label("Practice", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                Button {
                    showingListSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
            }
        }
    }

    private var wordsList: some View {
        List(selection: $selection) {
            ForEach(filteredWords, id: \.idValue) { word in
                NavigationLink {
                    AddWordView(listId: listId, learningLanguage: learningLanguage, originalLanguage: originalLanguage, ttsEnabled: ttsEnabled, word: word, onDelete: reload)
                } label: {
                    WordRow(word: word, learningLanguage: learningLanguage, ttsEnabled: ttsEnabled)
                }
            }
            .onDelete(perform: deleteWords)
        }
        .searchable(text: $searchText, prompt: "Search words".localized(preferredLanguage))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Words Yet", systemImage: "character.book.closed")
        } description: {
            Text("Add the words you're learning to “\(listName)”.")
        } actions: {
            Button("Add Your First Word") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func reload() {
        guard let uid = auth.uid else { return }
        Task { await vm.load(uid: uid, listId: listId) }
    }

    private func deleteWords(at offsets: IndexSet) {
        // Confirm before removing: stash the words and ask the user first.
        pendingDeleteWords = offsets.map { filteredWords[$0] }
        pendingDeleteIsSelection = false
        showingDeleteConfirm = true
    }

    private func cancelDelete() {
        pendingDeleteWords = []
        pendingDeleteIsSelection = false
    }

    private func confirmDelete() {
        guard let uid = auth.uid else { cancelDelete(); return }
        let toDelete = pendingDeleteWords
        let wasSelection = pendingDeleteIsSelection
        Task {
            for word in toDelete { await vm.delete(uid: uid, listId: listId, word: word) }
            if wasSelection { endSelection() }
        }
        pendingDeleteWords = []
        pendingDeleteIsSelection = false
    }

    private func renameList(to name: String) {
        guard let uid = auth.uid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        listName = trimmed
        Task { await vm.rename(uid: uid, listId: listId, to: trimmed) }
    }

    /// Persists the text-to-speech toggle. Applied immediately (like the filter),
    /// so there's nothing to confirm.
    private func setTTS(_ enabled: Bool) {
        guard let uid = auth.uid else { return }
        ttsEnabled = enabled
        Task {
            do { try await VocabRepository.setListTTS(uid: uid, listId: listId, enabled: enabled) }
            catch { vm.errorMessage = error.localizedDescription }
            // Re-evaluate every word's mastery under the new setting: enabling
            // requires pronunciation (so a word already memorized may become
            // unmemorized until its pronunciation count catches up), disabling
            // stops counting it while keeping the count.
            await vm.applyTTS(uid: uid, listId: listId, enabled: enabled)
        }
    }

    private func resetMemory() {
        guard let uid = auth.uid else { return }
        Task { await vm.resetAllMemory(uid: uid, listId: listId) }
    }

    private func beginSelection() {
        selection.removeAll()
        withAnimation { editMode = .active }
    }

    private func endSelection() {
        selection.removeAll()
        withAnimation { editMode = .inactive }
    }

    private func beginMove() {
        guard let uid = auth.uid else { return }
        Task {
            await vm.loadMoveTargets(uid: uid, current: list)
            showingMoveSheet = true
        }
    }

    private func moveSelected(to destination: VocabularyList) {
        guard let uid = auth.uid, let destId = destination.id else { return }
        let ids = selection
        Task {
            await vm.moveSelected(uid: uid, fromListId: listId, toListId: destId, ids: ids)
            endSelection()
        }
    }
}
