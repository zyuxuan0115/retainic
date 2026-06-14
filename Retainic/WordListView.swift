//
//  WordListView.swift
//  Retainic
//
//  Browse, add, edit, and delete vocabulary words.
//

import SwiftUI
import SwiftData

struct WordListView: View {
    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]

    @State private var showingAdd = false
    @State private var searchText = ""

    private var filteredWords: [Word] {
        guard !searchText.isEmpty else { return words }
        return words.filter {
            $0.term.localizedCaseInsensitiveContains(searchText) ||
            $0.translation.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredWords) { word in
                            NavigationLink {
                                AddWordView(word: word)
                            } label: {
                                WordRow(word: word)
                            }
                        }
                        .onDelete(perform: deleteWords)
                    }
                    .searchable(text: $searchText, prompt: "Search words")
                }
            }
            .navigationTitle("Words")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Word", systemImage: "plus")
                    }
                }
                if !words.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    AddWordView()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Words Yet", systemImage: "character.book.closed")
        } description: {
            Text("Add the words you're learning in \(Language.named(targetLanguage)?.name ?? "your new language") and their translations.")
        } actions: {
            Button("Add Your First Word") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func deleteWords(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredWords[index])
            }
        }
    }
}

private struct WordRow: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.term)
                .font(.headline)
            Text(word.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    WordListView()
        .modelContainer(for: Word.self, inMemory: true)
}
