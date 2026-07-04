//
//  ListDetailView.swift
//  Retainic
//
//  Words inside a single vocabulary list: add, edit, delete, and practice.
//

import SwiftUI
import Combine
import UIKit

/// Filters which words are shown in a list.
enum WordFilter: String, CaseIterable, Identifiable {
    case all, remembered, unremembered
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .all: return "Show all"
        case .remembered: return "Show remembered only"
        case .unremembered: return "Show unremembered only"
        }
    }
}

@MainActor
final class WordsViewModel: ObservableObject {
    @Published var words: [VocabWord] = []
    @Published var moveTargets: [VocabularyList] = []
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var errorMessage: String?

    func load(uid: String, listId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            words = try await VocabRepository.fetchWords(uid: uid, listId: listId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(uid: String, listId: String, word: VocabWord) async {
        guard let id = word.id else { return }
        do {
            try await VocabRepository.deleteWord(uid: uid, listId: listId, wordId: id)
            words.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lists the selected words can move to: same learning and original
    /// languages, and not the current list.
    func loadMoveTargets(uid: String, current: VocabularyList) async {
        do {
            let lists = try await VocabRepository.fetchLists(uid: uid)
            moveTargets = lists.filter { other in
                guard other.id != current.id else { return false }
                let sameLearning = other.learningLanguage == current.learningLanguage
                let sameOriginal = other.originalLanguage == current.originalLanguage
                return sameLearning && sameOriginal
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected(uid: String, listId: String, ids: Set<String>) async {
        isBusy = true
        defer { isBusy = false }
        do {
            for id in ids {
                try await VocabRepository.deleteWord(uid: uid, listId: listId, wordId: id)
            }
            words.removeAll { $0.id.map(ids.contains) ?? false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(uid: String, listId: String, to name: String) async {
        do {
            try await VocabRepository.renameList(uid: uid, listId: listId, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resets every word's progress so the whole list counts as not remembered.
    func resetAllMemory(uid: String, listId: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            var updated = words
            for i in updated.indices {
                updated[i].resetMemory()
                try await VocabRepository.updateWord(uid: uid, listId: listId, word: updated[i])
            }
            words = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveSelected(uid: String, fromListId: String, toListId: String, ids: Set<String>) async {
        isBusy = true
        defer { isBusy = false }
        do {
            for word in words where word.id.map(ids.contains) ?? false {
                try await VocabRepository.moveWord(uid: uid, fromListId: fromListId, toListId: toListId, word: word)
            }
            words.removeAll { $0.id.map(ids.contains) ?? false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
                AddWordView(listId: listId, learningLanguage: learningLanguage, originalLanguage: originalLanguage)
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
                ttsEnabled: $ttsEnabled,
                publicId: list.publicId,
                onSave: { renameList(to: $0) },
                onSetTTS: { setTTS($0) },
                onResetMemory: { resetMemory() }
            )
            .preferredLocale(preferredLanguage)
        }
        .alert("Something went wrong".localized(preferredLanguage), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK".localized(preferredLanguage), role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
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
                    AddWordView(listId: listId, learningLanguage: learningLanguage, originalLanguage: originalLanguage, word: word, onDelete: reload)
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

private struct WordRow: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @ObservedObject private var playback = AudioPlaybackStore.shared
    let word: VocabWord
    let learningLanguage: String
    /// Whether the list falls back to a synthesized voice for words with no
    /// recording.
    let ttsEnabled: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(word.term)
                        .font(.headline)
                    if let reading = word.reading {
                        Text(reading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(word.partOfSpeechValues) { pos in
                        Text(pos.label(for: preferredLanguage))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                Text(word.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let key = pronunciationKey {
                Spacer()
                Button {
                    activatePronunciation()
                } label: {
                    Image(systemName: playback.playingPath == key ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    /// The active-playback key for this word's pronunciation: its recording path,
    /// or a TTS key when the list falls back to a synthesized voice — nil when the
    /// word has neither.
    private var pronunciationKey: String? {
        if let path = word.audioPath { return path }
        if ttsEnabled { return AudioPlaybackStore.ttsKey(word.term) }
        return nil
    }

    private func activatePronunciation() {
        if let path = word.audioPath {
            playback.toggle(path: path)
        } else if ttsEnabled {
            playback.toggleSpeak(text: word.term, language: learningLanguage)
        }
    }
}

/// Per-list settings: rename the list and reset every word's remembered state.
private struct ListSettingsSheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @Binding private var filter: WordFilter
    @Binding private var ttsEnabled: Bool
    @State private var showingResetConfirm = false
    @State private var showingShareConfirm = false
    private let originalName: String
    let publicId: String?
    let onSave: (String) -> Void
    let onSetTTS: (Bool) -> Void
    let onResetMemory: () -> Void

    init(name: String, filter: Binding<WordFilter>, ttsEnabled: Binding<Bool>, publicId: String?, onSave: @escaping (String) -> Void, onSetTTS: @escaping (Bool) -> Void, onResetMemory: @escaping () -> Void) {
        _name = State(initialValue: name)
        _filter = filter
        _ttsEnabled = ttsEnabled
        self.originalName = name
        self.publicId = publicId
        self.onSave = onSave
        self.onSetTTS = onSetTTS
        self.onResetMemory = onResetMemory
    }

    /// Save is enabled only once the name is non-empty and actually differs from
    /// the list's current name — nothing to save otherwise.
    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != originalName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("List name") {
                    TextField("List name", text: $name)
                }

                Section("Show words") {
                    Picker("Show words", selection: $filter) {
                        ForEach(WordFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                }

                Section {
                    Toggle("Text-to-speech", isOn: Binding(
                        get: { ttsEnabled },
                        set: { onSetTTS($0) }
                    ))
                } footer: {
                    Text("Read words aloud with a synthesized voice when they have no recording.")
                }

                Section {
                    Button {
                        shareUniqueId()
                    } label: {
                        Label("Share List", systemImage: "square.and.arrow.up")
                    }
                    .disabled((publicId ?? "").isEmpty)
                } footer: {
                    Text("Copies this list's unique ID so others can recreate it.")
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Mark all as not remembered", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Every word in this list will show up again in practice for all methods.")
                }
            }
            .navigationTitle("List Settings".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .alert("Unique ID copied".localized(preferredLanguage), isPresented: $showingShareConfirm) {
                Button("OK".localized(preferredLanguage), role: .cancel) {}
            } message: {
                Text("Share it with others so they can create the exact same wordlist.")
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("List Settings".localized(preferredLanguage)).font(.headline)
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
                "Mark all words as not remembered?".localized(preferredLanguage),
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

    /// Copies the list's unique ID to the clipboard so it can be shared.
    private func shareUniqueId() {
        guard let id = publicId, !id.isEmpty else { return }
        UIPasteboard.general.string = id
        showingShareConfirm = true
    }
}

/// Picks a destination list for moving the selected words. Only lists with a
/// matching learning + original language are offered.
private struct MoveDestinationSheet: View {
    let targets: [VocabularyList]
    let count: Int
    let onSelect: (VocabularyList) -> Void

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if targets.isEmpty {
                    ContentUnavailableView {
                        Label("No Compatible Lists", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("You need another list with the same learning and native language to move these words.")
                    }
                } else {
                    List(targets) { list in
                        Button {
                            onSelect(list)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.stack.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(list.wordCount) words")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move %lld Words".localized(preferredLanguage, count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Move %lld Words".localized(preferredLanguage, count)).font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
            }
        }
    }
}
