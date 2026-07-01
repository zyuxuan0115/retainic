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

    func create(uid: String, name: String, learningLanguage: String, originalLanguage: String) async {
        do {
            try await VocabRepository.createList(
                uid: uid,
                name: name,
                learningLanguage: learningLanguage,
                originalLanguage: originalLanguage
            )
            await load(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trash(uid: String, list: VocabularyList) async {
        guard let id = list.id else { return }
        do {
            try await VocabRepository.trashList(uid: uid, listId: id)
            lists.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
            .navigationTitle("My Lists".localized(preferredLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                NewListSheet { name, learning, original in
                    createList(name: name, learningLanguage: learning, originalLanguage: original)
                }
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
            .alert("Something went wrong".localized(preferredLanguage), isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK".localized(preferredLanguage), role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
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

/// New-list form: name plus the language pair the list bridges. The original
/// (translation) language defaults to the user's native language.
private struct NewListSheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    let onCreate: (_ name: String, _ learningLanguage: String, _ originalLanguage: String) -> Void

    @State private var name = ""
    @State private var learningLanguage = ""
    @State private var originalLanguage = ""

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !learningLanguage.isEmpty
        && !originalLanguage.isEmpty
        && learningLanguage != originalLanguage
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("New List".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if originalLanguage.isEmpty { originalLanguage = preferredLanguage }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onCreate(name, learningLanguage, originalLanguage)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("Create"))
                    .disabled(!canCreate)
                }
            }
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
                Text("\(list.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Trash

@MainActor
final class TrashViewModel: ObservableObject {
    @Published var lists: [VocabularyList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(uid: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            lists = try await VocabRepository.fetchTrashedLists(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(uid: String, list: VocabularyList) async {
        guard let id = list.id else { return }
        do {
            try await VocabRepository.restoreList(uid: uid, listId: id)
            lists.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purge(uid: String, list: VocabularyList) async {
        guard let id = list.id else { return }
        do {
            try await VocabRepository.purgeList(uid: uid, listId: id)
            lists.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Lists that have been moved to the trash. Each can be restored (put back into
/// "My Lists") or permanently deleted.
struct TrashView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = TrashViewModel()

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @State private var pendingPurge: VocabularyList?

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
            .navigationTitle("Trash".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("Done"))
                }
            }
            .task(id: auth.uid) {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .refreshable {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .alert(
                "Delete Forever".localized(preferredLanguage),
                isPresented: Binding(
                    get: { pendingPurge != nil },
                    set: { if !$0 { pendingPurge = nil } }
                ),
                presenting: pendingPurge
            ) { list in
                Button("Delete Forever".localized(preferredLanguage), role: .destructive) {
                    purge(list)
                }
                Button("Cancel".localized(preferredLanguage), role: .cancel) { pendingPurge = nil }
            } message: { list in
                Text("“\(list.name)” will be permanently deleted. This can't be undone.")
            }
            .alert("Something went wrong".localized(preferredLanguage), isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK".localized(preferredLanguage), role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(vm.lists) { list in
                ListRow(list: list)
                    .swipeActions(edge: .leading) {
                        Button {
                            restore(list)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingPurge = list
                        } label: {
                            Label("Delete Forever", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Trash is Empty", systemImage: "trash")
        } description: {
            Text("Deleted lists are kept here until you restore or permanently delete them.")
        }
    }

    private func restore(_ list: VocabularyList) {
        guard let uid = auth.uid else { return }
        Task { await vm.restore(uid: uid, list: list) }
    }

    private func purge(_ list: VocabularyList) {
        guard let uid = auth.uid else { return }
        pendingPurge = nil
        Task { await vm.purge(uid: uid, list: list) }
    }
}

#Preview {
    VocabListsView()
        .environmentObject(AuthService())
}
