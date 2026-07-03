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

/// New-list form: create a list from scratch (name + language pair), or import a
/// copy of someone else's list by its shared unique ID. Import is a second step
/// (name the copy) and is non-interruptible while its words are being copied.
private struct NewListSheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    let uid: String?
    let onCreate: (_ name: String, _ learningLanguage: String, _ originalLanguage: String) -> Void
    let onImported: () -> Void

    private enum Mode: Hashable { case create, importById }

    @State private var mode: Mode = .create

    // Create
    @State private var name = ""
    @State private var learningLanguage = ""
    @State private var originalLanguage = ""

    // Import — step 1 (look up by ID)
    @State private var importId = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?

    // Import — step 2 (name the copy, then copy the words)
    @State private var pendingImport: SharedList?
    @State private var importName = ""
    @State private var isImporting = false
    @State private var importError: String?

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !learningLanguage.isEmpty
        && !originalLanguage.isEmpty
        && learningLanguage != originalLanguage
    }

    var body: some View {
        NavigationStack {
            if let pending = pendingImport {
                namingView(pending)
            } else {
                formView
            }
        }
    }

    // MARK: - Step 1: create or look up

    private var formView: some View {
        Form {
            Picker("", selection: $mode) {
                Text("Create new").tag(Mode.create)
                Text("Import by ID").tag(Mode.importById)
            }
            .pickerStyle(.segmented)

            if mode == .create {
                createSections
            } else {
                importSection
            }
        }
        .navigationTitle("New List".localized(preferredLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if originalLanguage.isEmpty { originalLanguage = preferredLanguage }
        }
        .toolbar { formToolbar }
    }

    @ViewBuilder private var createSections: some View {
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

    @ViewBuilder private var importSection: some View {
        Section {
            TextField("Paste the unique ID", text: $importId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Unique ID")
        } footer: {
            if let lookupError {
                Text(lookupError).foregroundStyle(.red)
            } else {
                Text("Enter the unique ID someone shared with you to add a copy of their wordlist.")
            }
        }
    }

    @ToolbarContentBuilder private var formToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("New List".localized(preferredLanguage)).font(.headline)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(Text("Cancel"))
        }
        ToolbarItem(placement: .confirmationAction) {
            if isLookingUp {
                ProgressView()
            } else if mode == .create {
                Button {
                    onCreate(name, learningLanguage, originalLanguage)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(Text("Create"))
                .disabled(!canCreate)
            } else {
                Button { lookUp() } label: { Image(systemName: "arrow.right") }
                    .accessibilityLabel(Text("Import"))
                    .disabled(importId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Step 2: name the imported copy

    private func namingView(_ shared: SharedList) -> some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Import successful")
                        .font(.title3.bold())
                    Text("Found a wordlist with \(shared.words.count) words. Name your copy below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("List name") {
                TextField("List name", text: $importName)
            }

            if let importError {
                Text(importError).foregroundStyle(.red)
            }
        }
        .navigationTitle("New List".localized(preferredLanguage))
        .navigationBarTitleDisplayMode(.inline)
        // Adding many words must not be interrupted: block swipe-to-dismiss and
        // the back/confirm controls while the copy runs.
        .interactiveDismissDisabled(isImporting)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("New List".localized(preferredLanguage)).font(.headline)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { pendingImport = nil } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("Cancel"))
                    .disabled(isImporting)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isImporting {
                    ProgressView()
                } else {
                    Button { performImport(shared) } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(Text("Add"))
                        .disabled(importName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func lookUp() {
        let id = importId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        isLookingUp = true
        lookupError = nil
        Task {
            do {
                if let shared = try await VocabRepository.fetchSharedList(publicId: id) {
                    importName = shared.list.name
                    pendingImport = shared
                } else {
                    lookupError = "No wordlist found for that ID. Check it and try again."
                        .localized(preferredLanguage)
                }
            } catch {
                lookupError = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    private func performImport(_ shared: SharedList) {
        guard let uid else { return }
        isImporting = true
        importError = nil
        Task {
            do {
                let trimmed = importName.trimmingCharacters(in: .whitespaces)
                let finalName = trimmed.isEmpty ? shared.list.name : trimmed
                let newListId = try await VocabRepository.createList(
                    uid: uid,
                    name: finalName,
                    learningLanguage: shared.list.learningLanguage ?? "",
                    originalLanguage: shared.list.originalLanguage ?? ""
                )
                for source in shared.words {
                    let word = VocabWord(
                        term: source.term,
                        translation: source.translation,
                        notes: source.notes,
                        partsOfSpeech: source.partOfSpeechValues,
                        hiragana: source.hiragana,
                        pinyin: source.pinyin
                    )
                    try await VocabRepository.addWord(uid: uid, listId: newListId, word: word)
                }
                isImporting = false
                onImported()
                dismiss()
            } catch {
                importError = error.localizedDescription
                isImporting = false
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

    /// Permanently deletes every list currently in the trash.
    func purgeAll(uid: String) async {
        for list in lists {
            guard let id = list.id else { continue }
            do { try await VocabRepository.purgeList(uid: uid, listId: id) }
            catch { errorMessage = error.localizedDescription }
        }
        lists.removeAll()
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
    @State private var isPurging = false
    @State private var showingEmptyConfirm = false

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
                ToolbarItem(placement: .principal) {
                    Text("Trash".localized(preferredLanguage)).font(.headline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !vm.lists.isEmpty {
                        Button(role: .destructive) {
                            showingEmptyConfirm = true
                        } label: {
                            Label("Empty Trash", systemImage: "trash.slash")
                        }
                        .disabled(isPurging)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Done"))
                    .disabled(isPurging)
                }
            }
            .alert("Empty Trash".localized(preferredLanguage), isPresented: $showingEmptyConfirm) {
                Button("Empty Trash".localized(preferredLanguage), role: .destructive) { emptyTrash() }
                Button("Cancel".localized(preferredLanguage), role: .cancel) {}
            } message: {
                Text("Permanently delete all lists in the Trash? This can't be undone.")
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
        // While purging, hold on a blocking "Deleting…" overlay: taps outside do
        // nothing and the panel can't be swiped away until the delete finishes.
        .overlay {
            if isPurging {
                ZStack {
                    Color(.systemBackground).opacity(0.6).ignoresSafeArea()
                    ProgressView("Deleting…".localized(preferredLanguage))
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .transition(.opacity)
            }
        }
        .interactiveDismissDisabled(isPurging)
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
        withAnimation { isPurging = true }
        Task {
            // Hold on the "Deleting…" overlay for a moment so the deletion is
            // perceptible, then perform it and only then dismiss the overlay.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await vm.purge(uid: uid, list: list)
            withAnimation { isPurging = false }
        }
    }

    private func emptyTrash() {
        guard let uid = auth.uid else { return }
        // Show the blocking "Deleting…" overlay and keep the user here until
        // every trashed list has been permanently removed.
        withAnimation { isPurging = true }
        Task {
            await vm.purgeAll(uid: uid)
            withAnimation { isPurging = false }
        }
    }
}

#Preview {
    VocabListsView()
        .environmentObject(AuthService())
}
