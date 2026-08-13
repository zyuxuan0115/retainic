package com.retainic.app.data

import com.google.android.gms.tasks.Task
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.QuerySnapshot
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.firestoreSettings
import com.google.firebase.firestore.persistentCacheSettings
import kotlinx.coroutines.tasks.await

/**
 * The two things that make Firestore usable with no connection. A port of
 * FirestoreOffline.swift.
 *
 * Reading: Firestore keeps everything the app has already fetched in an on-disk
 * cache, which is what lets you browse the lists and glossaries you have been
 * using. The helpers here fall back to that cache instead of failing, and skip
 * the round trip entirely when we already know we're offline.
 *
 * Writing: the SDK applies a write to the local cache at once but only completes
 * its Task once the *server* has acknowledged it. Awaiting one offline therefore
 * never returns — the screen would sit there spinning even though the change had
 * already been made locally and would sync on its own later. So when there's no
 * connection we start the write and return.
 */
object FirestoreOffline {
    /**
     * Enables the persistent cache explicitly and lifts its size cap. On by
     * default at 100 MB, but a large vocabulary with a long review history is
     * exactly the account we don't want evicting itself between sessions.
     * Must run before anything else touches Firestore.
     */
    fun configure() {
        FirebaseFirestore.getInstance().firestoreSettings = firestoreSettings {
            setLocalCacheSettings(
                persistentCacheSettings {
                    setSizeBytes(FirebaseFirestore.CACHE_SIZE_UNLIMITED)
                }
            )
        }
    }
}

// MARK: - Reads

/**
 * Runs the query against the server when there is a connection and against the
 * on-disk cache when there isn't — and if a request fails part-way (a dropped
 * connection mid-flight), serves the cache rather than the error, so browsing
 * keeps working.
 */
suspend fun Query.getOfflineSafe(): QuerySnapshot =
    if (!Connectivity.isOnlineNow) {
        get(Source.CACHE).await()
    } else {
        try {
            get(Source.DEFAULT).await()
        } catch (e: Exception) {
            get(Source.CACHE).await()
        }
    }

/** The single-document counterpart of [getOfflineSafe]. */
suspend fun DocumentReference.getDocOfflineSafe(): DocumentSnapshot =
    if (!Connectivity.isOnlineNow) {
        get(Source.CACHE).await()
    } else {
        try {
            get(Source.DEFAULT).await()
        } catch (e: Exception) {
            get(Source.CACHE).await()
        }
    }

// MARK: - Writes

/**
 * Awaits a write only while there is a connection. The Task has already been
 * issued by the time this is called — Firestore applied it to the local cache
 * and persisted the pending mutation itself, and replays it on reconnect — so
 * offline there is nothing to wait for.
 */
suspend fun Task<*>.awaitWrite() {
    if (Connectivity.isOnlineNow) await()
}
