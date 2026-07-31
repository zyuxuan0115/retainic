//
//  ListsViewModel.swift
//  Retainic
//
//  Repository-backed state for active vocabulary lists.
//

import Combine
import Foundation

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
