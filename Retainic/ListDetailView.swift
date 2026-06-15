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
    @Published var isLoading = false
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
}

struct ListDetailView: View {
    let list: VocabularyList

    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = WordsViewModel()

    @State private var showingAdd = false
    @State private var searchText = ""

    private var listId: String { list.id ?? "" }

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
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
            }
            if !vm.words.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    NavigationLink {
                        FlashcardView(listName: list.name, listId: listId, words: vm.words)
                    } label: {
                        Label("Practice", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
            }
        }
        .task(id: auth.uid) {
            if let uid = auth.uid { await vm.load(uid: uid, listId: listId) }
        }
        .refreshable {
            if let uid = auth.uid { await vm.load(uid: uid, listId: listId) }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            NavigationStack {
                AddWordView(listId: listId)
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

    private var wordsList: some View {
        List {
            ForEach(filteredWords) { word in
                NavigationLink {
                    AddWordView(listId: listId, word: word)
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
}

private struct WordRow: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""
    @ObservedObject private var playback = AudioPlaybackStore.shared
    let word: VocabWord

    private var partOfSpeech: PartOfSpeech? {
        let pos = word.partOfSpeechValue
        return pos == .unspecified ? nil : pos
    }

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
                    if let partOfSpeech {
                        Text(partOfSpeech.label(for: nativeLanguage))
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
