package com.retainic.app.data

import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * Firestore read/write helpers for glossaries and their entries. A port of
 * GlossaryRepository.swift, kept apart from [VocabRepository] because glossaries
 * share nothing with lists: no words, no audio, no shared-by-ID copies.
 */
object GlossaryRepository {
    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun glossariesRef(uid: String) =
        db.collection("users").document(uid).collection("glossaries")

    private fun entriesRef(uid: String, glossaryId: String) =
        glossariesRef(uid).document(glossaryId).collection("entries")

    // MARK: - Glossaries

    /** Active (non-trashed) glossaries, newest first. */
    suspend fun fetchGlossaries(uid: String): List<Glossary> {
        val snapshot = glossariesRef(uid)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .get().await()
        return snapshot.documents
            .mapNotNull { it.toObject(Glossary::class.java) }
            .filter { it.deletedAt == null }
    }

    /** Glossaries currently in the trash, most recently deleted first. */
    suspend fun fetchTrashedGlossaries(uid: String): List<Glossary> {
        val snapshot = glossariesRef(uid).get().await()
        return snapshot.documents
            .mapNotNull { it.toObject(Glossary::class.java) }
            .filter { it.deletedAt != null }
            .sortedByDescending { it.deletedAt?.time ?: Long.MIN_VALUE }
    }

    suspend fun createGlossary(uid: String, name: String, language: String): String {
        val glossary = Glossary(name = name, createdAt = Date(), entryCount = 0, language = language)
        val ref = glossariesRef(uid).add(glossary).await()
        return ref.id
    }

    suspend fun renameGlossary(uid: String, glossaryId: String, name: String) {
        glossariesRef(uid).document(glossaryId).update("name", name).await()
    }

    /** Soft-delete: move a glossary to the trash by stamping deletedAt. */
    suspend fun trashGlossary(uid: String, glossaryId: String) {
        glossariesRef(uid).document(glossaryId).update("deletedAt", FieldValue.serverTimestamp()).await()
    }

    /** Restore a trashed glossary by clearing its deletedAt stamp. */
    suspend fun restoreGlossary(uid: String, glossaryId: String) {
        glossariesRef(uid).document(glossaryId).update("deletedAt", FieldValue.delete()).await()
    }

    /** Permanently delete a glossary and its entries. */
    suspend fun purgeGlossary(uid: String, glossaryId: String) {
        val entries = entriesRef(uid, glossaryId).get().await()
        deleteDocuments(entries.documents.map { it.reference }, glossariesRef(uid).document(glossaryId))
    }

    /**
     * The most documents one delete batch holds: a batch takes 500 operations,
     * and the last one here spends its 500th on the glossary document.
     */
    private const val DELETE_BATCH_LIMIT = 499

    /**
     * Deletes many documents in batches — emptying the Trash of a long glossary
     * is one round trip per 499 terms instead of one per term. [parent] (the
     * glossary itself) goes last, in the final batch, so a failure part-way
     * through leaves it in the Trash to be purged again rather than orphaning
     * the terms still under it.
     */
    private suspend fun deleteDocuments(refs: List<DocumentReference>, parent: DocumentReference) {
        if (refs.isEmpty()) {
            parent.delete().await()
            return
        }
        val chunks = refs.chunked(DELETE_BATCH_LIMIT)
        for ((index, chunk) in chunks.withIndex()) {
            val batch = db.batch()
            for (ref in chunk) batch.delete(ref)
            if (index == chunks.lastIndex) batch.delete(parent)
            batch.commit().await()
        }
    }

    // MARK: - Entries

    /**
     * Every term the user has, across all their glossaries, fetched together
     * the way [VocabRepository.fetchAllWords] fetches words.
     */
    suspend fun fetchAllEntries(uid: String): List<GlossaryEntry> = coroutineScope {
        val glossaries = fetchGlossaries(uid)
        glossaries.mapNotNull { it.id }
            .map { id -> async { fetchEntries(uid, id) } }
            .awaitAll()
            .flatten()
    }

    suspend fun fetchEntries(uid: String, glossaryId: String): List<GlossaryEntry> {
        val snapshot = entriesRef(uid, glossaryId)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .get().await()
        return snapshot.documents.mapNotNull { it.toObject(GlossaryEntry::class.java) }
    }

    suspend fun addEntry(uid: String, glossaryId: String, entry: GlossaryEntry) {
        entriesRef(uid, glossaryId).add(entry.copy(id = null)).await()
        glossariesRef(uid).document(glossaryId).update("entryCount", FieldValue.increment(1)).await()
    }

    suspend fun updateEntry(uid: String, glossaryId: String, entry: GlossaryEntry) {
        val id = entry.id ?: return
        // Null the @DocumentId field so it isn't written into the document body.
        entriesRef(uid, glossaryId).document(id).set(entry.copy(id = null)).await()
    }

    suspend fun deleteEntry(uid: String, glossaryId: String, entryId: String) {
        entriesRef(uid, glossaryId).document(entryId).delete().await()
        glossariesRef(uid).document(glossaryId).update("entryCount", FieldValue.increment(-1)).await()
    }
}
