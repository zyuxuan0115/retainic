//
//  GlossariesView.swift
//  Retainic
//
//  Home for the signed-in user's glossaries: single-language decks of terms and
//  their definitions, kept separate from vocabulary lists.
//

import SwiftUI
import Combine

@MainActor
final class GlossariesViewModel: ObservableObject {
    @Published var glossaries: [Glossary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(uid: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            glossaries = try await GlossaryRepository.fetchGlossaries(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(uid: String, name: String, language: String) async {
        do {
            try await GlossaryRepository.createGlossary(uid: uid, name: name, language: language)
            await load(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trash(uid: String, glossary: Glossary) async {
        guard let id = glossary.id else { return }
        do {
            try await GlossaryRepository.trashGlossary(uid: uid, glossaryId: id)
            glossaries.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GlossariesView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = GlossariesViewModel()

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @State private var showingNewGlossary = false
    @State private var showingTrash = false
    @State private var pendingTrash: [Glossary] = []
    @State private var showingTrashConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.glossaries.isEmpty {
                    ProgressView("Loading…")
                } else if vm.glossaries.isEmpty {
                    emptyState
                } else {
                    glossaryContent
                }
            }
            .navigationTitle("Glossaries".localized(preferredLanguage))
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
                        showingNewGlossary = true
                    } label: {
                        Label("New Glossary", systemImage: "plus")
                    }
                }
            }
            .task(id: auth.uid) {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .refreshable {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .sheet(isPresented: $showingNewGlossary) {
                NewGlossarySheet { name, language in
                    createGlossary(name: name, language: language)
                }
                .preferredLocale(preferredLanguage)
            }
            .sheet(isPresented: $showingTrash, onDismiss: {
                // A restore puts a glossary back into the active set, so refresh.
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
            ) { glossaries in
                Button("Move to Trash".localized(preferredLanguage), role: .destructive) {
                    confirmTrash(glossaries)
                }
                Button("Cancel".localized(preferredLanguage), role: .cancel) { pendingTrash = [] }
            } message: { glossaries in
                if glossaries.count == 1 {
                    Text("“\(glossaries[0].name)” will be moved to the Trash.")
                } else {
                    Text("The selected glossaries will be moved to the Trash.")
                }
            }
        }
    }

    private var glossaryContent: some View {
        List {
            ForEach(vm.glossaries) { glossary in
                NavigationLink {
                    GlossaryDetailView(glossary: glossary)
                } label: {
                    GlossaryRow(glossary: glossary)
                }
            }
            .onDelete(perform: deleteGlossaries)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Glossaries Yet", systemImage: "character.book.closed.fill")
        } description: {
            Text("Create your first glossary to collect terms and what they mean.")
        } actions: {
            Button("Create a Glossary") {
                showingNewGlossary = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func createGlossary(name: String, language: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let uid = auth.uid else { return }
        Task { await vm.create(uid: uid, name: name, language: language) }
    }

    private func deleteGlossaries(at offsets: IndexSet) {
        // Confirm before removing: stash the glossaries and ask the user first.
        pendingTrash = offsets.map { vm.glossaries[$0] }
        showingTrashConfirm = true
    }

    private func confirmTrash(_ glossaries: [Glossary]) {
        guard let uid = auth.uid else { pendingTrash = []; return }
        Task {
            for glossary in glossaries { await vm.trash(uid: uid, glossary: glossary) }
        }
        pendingTrash = []
    }
}

/// Compact glossary summary shared by the active and trash screens.
struct GlossaryRow: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    let glossary: Glossary

    var body: some View {
        HStack {
            Image(systemName: "character.book.closed.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(glossary.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(glossary.entryCount) terms")
                    if let code = glossary.language, let language = Language.named(code) {
                        Text("·")
                        Text(language.displayName(in: preferredLanguage))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Names a new glossary and picks the one language its terms are written in.
struct NewGlossarySheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    let onCreate: (_ name: String, _ language: String) -> Void

    @State private var name = ""
    @State private var language = ""

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !language.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Glossary name") {
                    TextField("e.g. Legal terms", text: $name)
                }
                Section {
                    // A glossary is monolingual: terms and definitions are both
                    // written in this one language, so there is no translation
                    // language to pick.
                    Picker("Terms are in", selection: $language) {
                        Text("Select…").tag("")
                        ForEach(Language.all) { option in
                            Text(option.displayName(in: preferredLanguage)).tag(option.code)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Terms and definitions are both written in this language.")
                }
            }
            .navigationTitle("New Glossary".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if language.isEmpty { language = preferredLanguage }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Glossary".localized(preferredLanguage)).font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onCreate(name, language)
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

#Preview {
    GlossariesView()
        .environmentObject(AuthService())
}
