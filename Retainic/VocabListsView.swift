//
//  VocabListsView.swift
//  Retainic
//
//  Post-login home: all vocabulary lists the signed-in user created.
//

import SwiftUI
import Combine

@MainActor
final class ListsViewModel: ObservableObject {
    @Published var lists: [VocabularyList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(uid: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            lists = try await VocabRepository.fetchLists(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(uid: String, name: String) async {
        do {
            try await VocabRepository.createList(uid: uid, name: name)
            await load(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(uid: String, list: VocabularyList) async {
        guard let id = list.id else { return }
        do {
            try await VocabRepository.deleteList(uid: uid, listId: id)
            lists.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VocabListsView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = ListsViewModel()

    @State private var showingNewList = false
    @State private var newListName = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.lists.isEmpty {
                    ProgressView("Loading…")
                } else if vm.lists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("My Lists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newListName = ""
                        showingNewList = true
                    } label: {
                        Label("New List", systemImage: "plus")
                    }
                }
            }
            .task(id: auth.uid) {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .refreshable {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .alert("New List", isPresented: $showingNewList) {
                TextField("List name", text: $newListName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createList() }
            } message: {
                Text("Name your new vocabulary list.")
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
    }

    private var listContent: some View {
        List {
            ForEach(vm.lists) { list in
                NavigationLink {
                    ListDetailView(list: list)
                } label: {
                    ListRow(list: list)
                }
            }
            .onDelete(perform: deleteLists)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lists Yet", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Create your first vocabulary list to start adding words.")
        } actions: {
            Button("Create a List") {
                newListName = ""
                showingNewList = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let uid = auth.uid else { return }
        Task { await vm.create(uid: uid, name: name) }
    }

    private func deleteLists(at offsets: IndexSet) {
        guard let uid = auth.uid else { return }
        let toDelete = offsets.map { vm.lists[$0] }
        Task {
            for list in toDelete { await vm.delete(uid: uid, list: list) }
        }
    }
}

private struct ListRow: View {
    let list: VocabularyList

    var body: some View {
        HStack {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.headline)
                Text("\(list.wordCount) word\(list.wordCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    VocabListsView()
        .environmentObject(AuthService())
}
