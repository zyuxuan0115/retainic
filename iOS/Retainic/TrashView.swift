//
//  TrashView.swift
//  Retainic
//
//  Restore and permanent-deletion flows for trashed lists.
//

import SwiftUI
import Combine

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
            .repositoryErrorAlert($vm.errorMessage, language: preferredLanguage)
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
