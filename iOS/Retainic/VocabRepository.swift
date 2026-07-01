//
//  VocabRepository.swift
//  Retainic
//
//  Firestore read/write helpers for vocabulary lists and words.
//

import Foundation
import CryptoKit
import FirebaseFirestore
import FirebaseStorage

enum VocabRepository {
    private static var db: Firestore { Firestore.firestore() }

    static func userDoc(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    /// Whether the given invitation code exists (registration gate). Codes are
    /// stored as document IDs under `invitationCodes`; security rules allow a
    /// single-doc `get` but forbid listing, so the set can't be enumerated.
    static func isValidInvitationCode(_ code: String) async -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let snapshot = try await db.collection("invitationCodes").document(trimmed).getDocument()
            return snapshot.exists
        } catch {
            return false
        }
    }

    private static func listsRef(_ uid: String) -> CollectionReference {
        userDoc(uid).collection("lists")
    }

    private static func wordsRef(_ uid: String, _ listId: String) -> CollectionReference {
        listsRef(uid).document(listId).collection("words")
    }

    // MARK: - Daily stats

    /// "yyyy-MM-dd" key in the device's calendar, used for daily-stat documents.
    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    private static func dailyStatsRef(_ uid: String) -> CollectionReference {
        userDoc(uid).collection("dailyStats")
    }

    /// Increments today's remembered count for the given aspect.
    static func recordRemembered(uid: String, aspect: String, on date: Date = Date()) async throws {
        let field: String
        switch aspect {
        case "spelling": field = "word"
        case "translation": field = "translation"
        case "pronunciation": field = "pronunciation"
        default: return
        }
        let key = dayKey(date)
        try await dailyStatsRef(uid).document(key).setData([
            "date": key,
            field: FieldValue.increment(Int64(1))
        ], merge: true)
    }

    /// Most recent `days` daily-stat documents (chronological order).
    static func fetchDailyStats(uid: String, days: Int) async throws -> [DailyStat] {
        let snapshot = try await dailyStatsRef(uid)
            .order(by: "date", descending: true)
            .limit(to: days)
            .getDocuments()
        let stats = snapshot.documents.compactMap { try? $0.data(as: DailyStat.self) }
        return stats.sorted { $0.date < $1.date }
    }

    // MARK: - Lists

    /// A stable per-list identifier: a 64-character SHA-256 hex string (letters
    /// and numbers only), independent of the Firestore document ID.
    static func generateListPublicId() -> String {
        let seed = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        return SHA256.hash(data: seed).map { String(format: "%02x", $0) }.joined()
    }

    /// Ensures each list has a `publicId`, generating and persisting one for any
    /// that predate the field. Best-effort: a failed write won't break the read.
    private static func backfillPublicIds(uid: String, lists: inout [VocabularyList]) async {
        for i in lists.indices where (lists[i].publicId?.isEmpty ?? true) {
            guard let id = lists[i].id else { continue }
            let publicId = generateListPublicId()
            lists[i].publicId = publicId
            try? await listsRef(uid).document(id).updateData(["publicId": publicId])
        }
    }

    /// Active (non-trashed) lists, newest first. Trashed lists carry a
    /// `deletedAt` timestamp and are filtered out here — see `fetchTrashedLists`.
    static func fetchLists(uid: String) async throws -> [VocabularyList] {
        let snapshot = try await listsRef(uid)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        var lists = snapshot.documents
            .compactMap { try? $0.data(as: VocabularyList.self) }
            .filter { $0.deletedAt == nil }
        await backfillPublicIds(uid: uid, lists: &lists)
        return lists
    }

    /// Lists currently in the trash, most recently deleted first.
    static func fetchTrashedLists(uid: String) async throws -> [VocabularyList] {
        let snapshot = try await listsRef(uid).getDocuments()
        var lists = snapshot.documents
            .compactMap { try? $0.data(as: VocabularyList.self) }
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        await backfillPublicIds(uid: uid, lists: &lists)
        return lists
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
            originalLanguage: originalLanguage,
            publicId: generateListPublicId()
        )
        let ref = try listsRef(uid).addDocument(from: list)
        return ref.documentID
    }

    static func renameList(uid: String, listId: String, name: String) async throws {
        try await listsRef(uid).document(listId).updateData(["name": name])
    }

    /// Soft-delete: move a list to the trash by stamping `deletedAt`. Its words
    /// and audio are left untouched so the list can be restored intact.
    static func trashList(uid: String, listId: String) async throws {
        try await listsRef(uid).document(listId)
            .updateData(["deletedAt": FieldValue.serverTimestamp()])
    }

    /// Restore a trashed list by clearing its `deletedAt` stamp.
    static func restoreList(uid: String, listId: String) async throws {
        try await listsRef(uid).document(listId)
            .updateData(["deletedAt": FieldValue.delete()])
    }

    /// Permanently delete a list, its words, and any pronunciation audio.
    static func purgeList(uid: String, listId: String) async throws {
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
            word.refreshMemorizationForAudio()
        } else if removeAudio {
            await deleteAudio(path: path)
            word.audioPath = nil
            word.refreshMemorizationForAudio()
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
        // Cache the clip on-device/CDN so repeat playback doesn't re-download.
        metadata.cacheControl = "public, max-age=604800"
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
