//
//  VocabRepository.swift
//  Retainic
//
//  Firestore read/write helpers for vocabulary lists and words.
//

import Foundation
import FirebaseFirestore

enum VocabRepository {
    private static var db: Firestore { Firestore.firestore() }

    static func userDoc(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private static func listsRef(_ uid: String) -> CollectionReference {
        userDoc(uid).collection("lists")
    }

    private static func wordsRef(_ uid: String, _ listId: String) -> CollectionReference {
        listsRef(uid).document(listId).collection("words")
    }

    // MARK: - Lists

    static func fetchLists(uid: String) async throws -> [VocabularyList] {
        let snapshot = try await listsRef(uid)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: VocabularyList.self) }
    }

    @discardableResult
    static func createList(uid: String, name: String) async throws -> String {
        let list = VocabularyList(name: name, createdAt: Date(), wordCount: 0)
        let ref = try listsRef(uid).addDocument(from: list)
        return ref.documentID
    }

    static func renameList(uid: String, listId: String, name: String) async throws {
        try await listsRef(uid).document(listId).updateData(["name": name])
    }

    static func deleteList(uid: String, listId: String) async throws {
        // Remove the words subcollection first, then the list document.
        let words = try await wordsRef(uid, listId).getDocuments()
        for doc in words.documents {
            try await doc.reference.delete()
        }
        try await listsRef(uid).document(listId).delete()
    }

    // MARK: - Words

    static func fetchWords(uid: String, listId: String) async throws -> [VocabWord] {
        let snapshot = try await wordsRef(uid, listId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: VocabWord.self) }
    }

    static func addWord(uid: String, listId: String, word: VocabWord) async throws {
        _ = try wordsRef(uid, listId).addDocument(from: word)
        try await listsRef(uid).document(listId)
            .updateData(["wordCount": FieldValue.increment(Int64(1))])
    }

    static func updateWord(uid: String, listId: String, word: VocabWord) async throws {
        guard let id = word.id else { return }
        try wordsRef(uid, listId).document(id).setData(from: word, merge: true)
    }

    static func deleteWord(uid: String, listId: String, wordId: String) async throws {
        try await wordsRef(uid, listId).document(wordId).delete()
        try await listsRef(uid).document(listId)
            .updateData(["wordCount": FieldValue.increment(Int64(-1))])
    }
}
