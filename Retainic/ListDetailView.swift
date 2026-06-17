//
//  ListDetailView.swift
//  Retainic
//
//  Words inside a single vocabulary list: add, edit, delete, and practice.
//

import SwiftUI
import Combine

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

    @State private var showingAdd = false
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showingMoveSheet = false

    private var listId: String { list.id ?? "" }
    private var learningLanguage: String { list.learningLanguage ?? "" }
    private var originalLanguage: String { list.originalLanguage ?? "" }
    private var isSelecting: Bool { editMode == .active }

    private var practiceCards: [PracticeCard] {
        vm.words.map { PracticeCard(word: $0, listId: listId) }
    }

    private var filteredWords: [VocabWord] {
        guard !searchText.isEmpty else { return vm.words }
        return vm.words.filter {
            $0.term.localizedCaseInsensitiveContains(searchText) ||
            $0.translation.localizedCaseInsensitiveContains(searchText)
        }
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
        .navigationTitle(isSelecting ? selectionTitle : list.name)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar { toolbarContent }
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
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveDestinationSheet(
                targets: vm.moveTargets,
                count: selection.count
            ) { destination in
                moveSelected(to: destination)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var selectionTitle: String {
        selection.isEmpty ? "Select Words" : "\(selection.count) Selected"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { endSelection() }
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
                    deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty || vm.isBusy)
            }
        } else {
            if !vm.words.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        FlashcardView(cards: practiceCards, learningLanguage: learningLanguage)
                    } label: {
                        Label("Practice", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !vm.words.isEmpty {
                    Button {
                        beginSelection()
                    } label: {
                        Label("Select", systemImage: "checklist")
                    }
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
                    AddWordView(listId: listId, learningLanguage: learningLanguage, originalLanguage: originalLanguage, word: word)
                } label: {
                    WordRow(word: word)
                }
            }
            .onDelete(perform: deleteWords)
        }
        .searchable(text: $searchText, prompt: "Search words")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Words Yet", systemImage: "character.book.closed")
        } description: {
            Text("Add the words you're learning to “\(list.name)”.")
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
        guard let uid = auth.uid else { return }
        let toDelete = offsets.map { filteredWords[$0] }
        Task {
            for word in toDelete { await vm.delete(uid: uid, listId: listId, word: word) }
        }
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

    private func deleteSelected() {
        guard let uid = auth.uid else { return }
        let ids = selection
        Task {
            await vm.deleteSelected(uid: uid, listId: listId, ids: ids)
            endSelection()
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
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""
    @ObservedObject private var playback = AudioPlaybackStore.shared
    let word: VocabWord

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
                        Text(pos.label(for: nativeLanguage))
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
            if let path = word.audioPath {
                Spacer()
                Button {
                    playback.toggle(path: path)
                } label: {
                    Image(systemName: playback.playingPath == path ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Picks a destination list for moving the selected words. Only lists with a
/// matching learning + original language are offered.
private struct MoveDestinationSheet: View {
    let targets: [VocabularyList]
    let count: Int
    let onSelect: (VocabularyList) -> Void

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
                                    Text("\(list.wordCount) word\(list.wordCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move \(count) Word\(count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
