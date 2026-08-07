package com.retainic.app.data

import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
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
        for (doc in entries.documents) doc.reference.delete().await()
        glossariesRef(uid).document(glossaryId).delete().await()
    }

    // MARK: - Entries

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
