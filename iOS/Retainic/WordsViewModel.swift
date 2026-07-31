//
//  WordsViewModel.swift
//  Retainic
//
//  Word-list filtering and repository-backed state.
//

import SwiftUI
import Combine

/// Filters which words are shown in a list.
enum WordFilter: String, CaseIterable, Identifiable {
    case all, remembered, unremembered
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .all: return "Show all"
        case .remembered: return "Show remembered only"
        case .unremembered: return "Show unremembered only"
        }
    }
}

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

    func rename(uid: String, listId: String, to name: String) async {
        do {
            try await VocabRepository.renameList(uid: uid, listId: listId, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the list's text-to-speech setting to every word's mastery.
    /// Turning it on adds the pronunciation requirement (demoting any word
    /// mastered without it); turning it off drops the requirement while keeping
    /// each word's pronunciation count. Recomputes and persists `remember_final`
    /// so filters and stats reflect the new setting immediately.
    func applyTTS(uid: String, listId: String, enabled: Bool) async {
        isBusy = true
        defer { isBusy = false }
        do {
            var updated = words
            for i in updated.indices {
                updated[i].refreshMemorization(ttsEnabled: enabled)
                try await VocabRepository.updateWord(uid: uid, listId: listId, word: updated[i], ttsEnabled: enabled)
            }
            words = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resets every word's progress so the whole list counts as not remembered.
    func resetAllMemory(uid: String, listId: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            var updated = words
            for i in updated.indices {
                updated[i].resetMemory()
                try await VocabRepository.updateWord(uid: uid, listId: listId, word: updated[i])
            }
            words = updated
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
