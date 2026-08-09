//
//  VocabListsView.swift
//  Retainic
//
//  Post-login home for the signed-in user's vocabulary lists.
//

import SwiftUI

struct VocabListsView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = ListsViewModel()

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @State private var showingNewList = false
    @State private var showingTrash = false
    @State private var pendingTrash: [VocabularyList] = []
    @State private var showingTrashConfirm = false

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
            .navigationTitle("Lists".localized(preferredLanguage))
            // Inline, so the title shares the bar with the trash and plus
            // buttons; a large title would sit on its own line beneath them.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Both actions sit at the trailing edge, leaving the title
                // the whole leading side. The plus stays rightmost.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTrash = true
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
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
            .sheet(isPresented: $showingNewList) {
                NewListSheet(
                    uid: auth.uid,
                    onCreate: { name, learning, original in
                        createList(name: name, learningLanguage: learning, originalLanguage: original)
                    },
                    onImported: {
                        if let uid = auth.uid { Task { await vm.load(uid: uid) } }
                    }
                )
                .preferredLocale(preferredLanguage)
            }
            .sheet(isPresented: $showingTrash, onDismiss: {
                // A restore puts a list back into the active set, so refresh.
                if let uid = auth.uid { Task { await vm.load(uid: uid) } }
            }) {
                TrashView()
                    .environmentObject(auth)
                    .preferredLocale(preferredLanguage)
            }
            .repositoryErrorAlert($vm.errorMessage, language: preferredLanguage)
            .alert(
                "Move to Trash".localized(preferredLanguage),
                isPresented: $showingTrashConfirm,
                presenting: pendingTrash
            ) { lists in
                Button("Move to Trash".localized(preferredLanguage), role: .destructive) {
                    confirmTrash(lists)
                }
                Button("Cancel".localized(preferredLanguage), role: .cancel) { pendingTrash = [] }
            } message: { lists in
                if lists.count == 1 {
                    Text("“\(lists[0].name)” will be moved to the Trash.")
                } else {
                    Text("The selected lists will be moved to the Trash.")
                }
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
                showingNewList = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func createList(name: String, learningLanguage: String, originalLanguage: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let uid = auth.uid else { return }
        Task {
            await vm.create(
                uid: uid,
                name: name,
                learningLanguage: learningLanguage,
                originalLanguage: originalLanguage
            )
        }
    }

    private func deleteLists(at offsets: IndexSet) {
        // Confirm before removing: stash the lists and ask the user first.
        pendingTrash = offsets.map { vm.lists[$0] }
        showingTrashConfirm = true
    }

    private func confirmTrash(_ lists: [VocabularyList]) {
        guard let uid = auth.uid else { pendingTrash = []; return }
        Task {
            for list in lists { await vm.trash(uid: uid, list: list) }
        }
        pendingTrash = []
    }
}

/// Compact list summary shared by the active-list and trash screens.
struct ListRow: View {
    let list: VocabularyList

    var body: some View {
        HStack {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.headline)
                Text("\(list.wordCount) words")
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
