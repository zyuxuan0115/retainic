//
//  VocabRepository.swift
//  Retainic
//
//  Firestore read/write helpers for vocabulary lists and words.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

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
    static func createList(
        uid: String,
        name: String,
        learningLanguage: String,
        originalLanguage: String
    ) async throws -> String {
        let list = VocabularyList(
            name: name,
            createdAt: Date(),
            wordCount: 0,
            learningLanguage: learningLanguage,
            originalLanguage: originalLanguage
        )
        let ref = try listsRef(uid).addDocument(from: list)
        return ref.documentID
    }

    static func renameList(uid: String, listId: String, name: String) async throws {
        try await listsRef(uid).document(listId).updateData(["name": name])
    }

    static func deleteList(uid: String, listId: String) async throws {
        // Remove the words subcollection (and any pronunciation audio) first,
        // then the list document.
        let words = try await wordsRef(uid, listId).getDocuments()
        for doc in words.documents {
            await deleteAudio(path: audioStoragePath(uid: uid, listId: listId, wordId: doc.documentID))
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

    static func addWord(uid: String, listId: String, word: VocabWord, audioFileURL: URL? = nil) async throws {
        let ref = wordsRef(uid, listId).document()
        var word = word
        if let audioFileURL {
            let path = audioStoragePath(uid: uid, listId: listId, wordId: ref.documentID)
            try await uploadAudio(localURL: audioFileURL, to: path)
            word.audioPath = path
        }
        try ref.setData(from: word)
        try await listsRef(uid).document(listId)
            .updateData(["wordCount": FieldValue.increment(Int64(1))])
    }

    /// Updates a word. Pass `newAudioFileURL` to (re)upload a recording, or
    /// `removeAudio: true` to delete the existing recording. With neither, the
    /// existing `audioPath` is preserved (used for spaced-repetition updates).
    static func updateWord(
        uid: String,
        listId: String,
        word: VocabWord,
        newAudioFileURL: URL? = nil,
        removeAudio: Bool = false
    ) async throws {
        guard let id = word.id else { return }
        var word = word
        let path = audioStoragePath(uid: uid, listId: listId, wordId: id)
        if let newAudioFileURL {
            try await uploadAudio(localURL: newAudioFileURL, to: path)
            word.audioPath = path
        } else if removeAudio {
            await deleteAudio(path: path)
            word.audioPath = nil
        }
        // Full overwrite (no merge) so a cleared audioPath is actually removed.
        try wordsRef(uid, listId).document(id).setData(from: word)
    }

    static func deleteWord(uid: String, listId: String, wordId: String) async throws {
        await deleteAudio(path: audioStoragePath(uid: uid, listId: listId, wordId: wordId))
        try await wordsRef(uid, listId).document(wordId).delete()
        try await listsRef(uid).document(listId)
            .updateData(["wordCount": FieldValue.increment(Int64(-1))])
    }

    /// Moves a word from one list to another, preserving its fields, review
    /// progress and pronunciation audio. The audio is copied to the destination
    /// path before the source word (and its audio) are removed.
    static func moveWord(uid: String, fromListId: String, toListId: String, word: VocabWord) async throws {
        guard let wordId = word.id, fromListId != toListId else { return }

        var newWord = word
        newWord.id = nil
        newWord.audioPath = nil

        var localAudioURL: URL?
        if let audioPath = word.audioPath {
            let data = try await downloadAudioData(path: audioPath)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".m4a")
            try data.write(to: tmp)
            localAudioURL = tmp
        }

        try await addWord(uid: uid, listId: toListId, word: newWord, audioFileURL: localAudioURL)
        if let localAudioURL { try? FileManager.default.removeItem(at: localAudioURL) }
        try await deleteWord(uid: uid, listId: fromListId, wordId: wordId)
    }

    // MARK: - Pronunciation audio (Firebase Storage)

    static func audioStoragePath(uid: String, listId: String, wordId: String) -> String {
        "users/\(uid)/lists/\(listId)/words/\(wordId)/pronunciation.m4a"
    }

    private static func uploadAudio(localURL: URL, to path: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "audio/mp4"
        _ = try await Storage.storage().reference(withPath: path)
            .putFileAsync(from: localURL, metadata: metadata)
    }

    static func downloadAudioData(path: String) async throws -> Data {
        try await Storage.storage().reference(withPath: path).data(maxSize: 10 * 1024 * 1024)
    }

    private static func deleteAudio(path: String) async {
        try? await Storage.storage().reference(withPath: path).delete()
    }
}
