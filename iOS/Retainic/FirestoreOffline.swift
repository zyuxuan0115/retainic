//
//  FirestoreOffline.swift
//  Retainic
//
//  The two things that make Firestore usable with no connection.
//
//  Reading: Firestore keeps everything the app has already fetched in an
//  on-disk cache, which is what lets you browse the lists and glossaries you
//  have been using. The helpers here fall back to that cache instead of
//  failing, and skip the round trip entirely when we already know we're offline.
//
//  Writing: the SDK applies a write to the local cache at once but only calls
//  back once the *server* has acknowledged it. Awaiting one offline therefore
//  never returns — the screen would sit there spinning even though the change
//  had already been made locally and would sync on its own later. So when
//  there's no connection we start the write and return.
//

import FirebaseFirestore

// MARK: - Setup

enum FirestoreOffline {
    /// Enables the persistent cache explicitly and lifts its size cap. On by
    /// default at 100 MB, but a large vocabulary with a long review history is
    /// exactly the account we don't want evicting itself between sessions.
    /// Must run before anything else touches Firestore.
    static func configure() {
        let db = Firestore.firestore()
        let settings = db.settings
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited)
        )
        db.settings = settings
    }
}

// MARK: - Reads

extension Query {
    /// Runs the query against the server when there is a connection and against
    /// the on-disk cache when there isn't — and if a request fails part-way
    /// (a dropped connection mid-flight), serves the cache rather than the
    /// error, so browsing keeps working.
    func getDocumentsOfflineSafe() async throws -> QuerySnapshot {
        if !Connectivity.shared.isOnlineNow {
            return try await getDocuments(source: .cache)
        }
        do {
            return try await getDocuments(source: .default)
        } catch {
            return try await getDocuments(source: .cache)
        }
    }
}

extension DocumentReference {
    /// The single-document counterpart of `getDocumentsOfflineSafe`.
    func getDocumentOfflineSafe() async throws -> DocumentSnapshot {
        if !Connectivity.shared.isOnlineNow {
            return try await getDocument(source: .cache)
        }
        do {
            return try await getDocument(source: .default)
        } catch {
            return try await getDocument(source: .cache)
        }
    }
}

// MARK: - Writes

extension DocumentReference {
    func updateDataOfflineSafe(_ fields: [String: Any]) async throws {
        guard Connectivity.shared.isOnlineNow else {
            queueWhileOffline { self.updateDataNow(fields) }
            return
        }
        try await updateData(fields)
    }

    func setDataOfflineSafe(_ documentData: [String: Any], merge: Bool) async throws {
        guard Connectivity.shared.isOnlineNow else {
            queueWhileOffline { self.setDataNow(documentData, merge: merge) }
            return
        }
        try await setData(documentData, merge: merge)
    }

    func deleteOfflineSafe() async throws {
        guard Connectivity.shared.isOnlineNow else {
            queueWhileOffline { self.deleteNow() }
            return
        }
        try await delete()
    }
}

extension WriteBatch {
    func commitOfflineSafe() async throws {
        guard Connectivity.shared.isOnlineNow else {
            queueWhileOffline { self.commitNow() }
            return
        }
        try await commit()
    }
}

// MARK: - Selecting the callback-free overloads

// Each Firestore write comes in two shapes: one that reports back when the
// server has it, and one that doesn't. In an async context Swift resolves the
// bare call to the awaiting overload, so the fire-and-forget versions are
// reached through these plain, non-async methods instead.

private extension DocumentReference {
    func updateDataNow(_ fields: [String: Any]) { updateData(fields) }
    func setDataNow(_ documentData: [String: Any], merge: Bool) { setData(documentData, merge: merge) }
    func deleteNow() { delete() }
}

private extension WriteBatch {
    func commitNow() { commit() }
}

/// Runs a write without waiting for it: Firestore has already applied it to the
/// local cache and persists the pending mutation itself, replaying it when the
/// device reconnects.
private func queueWhileOffline(_ write: () -> Void) {
    write()
}
