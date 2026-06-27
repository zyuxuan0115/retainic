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

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @State private var showingNewList = false

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
        guard let uid = auth.uid else { return }
        let toDelete = offsets.map { vm.lists[$0] }
        Task {
            for list in toDelete { await vm.delete(uid: uid, list: list) }
        }
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

#Preview {
    VocabListsView()
        .environmentObject(AuthService())
}
