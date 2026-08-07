//
//  GlossaryRepository.swift
//  Retainic
//
//  Firestore read/write helpers for glossaries and their entries. Kept apart
//  from VocabRepository because glossaries share nothing with lists: no words,
//  no audio, no shared-by-ID copies.
//

import Foundation
import FirebaseFirestore

enum GlossaryRepository {
    private static var db: Firestore { Firestore.firestore() }

    private static func glossariesRef(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("glossaries")
    }

    private static func entriesRef(_ uid: String, _ glossaryId: String) -> CollectionReference {
        glossariesRef(uid).document(glossaryId).collection("entries")
    }

    // MARK: - Glossaries

    /// Active (non-trashed) glossaries, newest first.
    static func fetchGlossaries(uid: String) async throws -> [Glossary] {
        let snapshot = try await glossariesRef(uid)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: Glossary.self) }
            .filter { $0.deletedAt == nil }
    }

    /// Glossaries currently in the trash, most recently deleted first.
    static func fetchTrashedGlossaries(uid: String) async throws -> [Glossary] {
        let snapshot = try await glossariesRef(uid).getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: Glossary.self) }
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    @discardableResult
    static func createGlossary(uid: String, name: String, language: String) async throws -> String {
        let glossary = Glossary(name: name, createdAt: Date(), entryCount: 0, language: language)
        let ref = try glossariesRef(uid).addDocument(from: glossary)
        return ref.documentID
    }

    static func renameGlossary(uid: String, glossaryId: String, name: String) async throws {
        try await glossariesRef(uid).document(glossaryId).updateData(["name": name])
    }

    /// Soft-delete: move a glossary to the trash by stamping `deletedAt`. Its
    /// entries are left untouched so it can be restored intact.
    static func trashGlossary(uid: String, glossaryId: String) async throws {
        try await glossariesRef(uid).document(glossaryId)
            .updateData(["deletedAt": FieldValue.serverTimestamp()])
    }

    /// Restore a trashed glossary by clearing its `deletedAt` stamp.
    static func restoreGlossary(uid: String, glossaryId: String) async throws {
        try await glossariesRef(uid).document(glossaryId)
            .updateData(["deletedAt": FieldValue.delete()])
    }

    /// Permanently delete a glossary and its entries.
    static func purgeGlossary(uid: String, glossaryId: String) async throws {
        let entries = try await entriesRef(uid, glossaryId).getDocuments()
        for doc in entries.documents { try await doc.reference.delete() }
        try await glossariesRef(uid).document(glossaryId).delete()
    }

    // MARK: - Entries

    static func fetchEntries(uid: String, glossaryId: String) async throws -> [GlossaryEntry] {
        let snapshot = try await entriesRef(uid, glossaryId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: GlossaryEntry.self) }
    }

    static func addEntry(uid: String, glossaryId: String, entry: GlossaryEntry) async throws {
        try entriesRef(uid, glossaryId).addDocument(from: entry)
        try await glossariesRef(uid).document(glossaryId)
            .updateData(["entryCount": FieldValue.increment(Int64(1))])
    }

    static func updateEntry(uid: String, glossaryId: String, entry: GlossaryEntry) async throws {
        guard let id = entry.id else { return }
        try entriesRef(uid, glossaryId).document(id).setData(from: entry)
    }

    static func deleteEntry(uid: String, glossaryId: String, entryId: String) async throws {
        try await entriesRef(uid, glossaryId).document(entryId).delete()
        try await glossariesRef(uid).document(glossaryId)
            .updateData(["entryCount": FieldValue.increment(Int64(-1))])
    }
}
