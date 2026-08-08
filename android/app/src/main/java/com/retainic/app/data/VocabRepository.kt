package com.retainic.app.data

import android.net.Uri
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.tasks.await
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Firestore + Storage read/write helpers for vocabulary lists and words.
 * A direct port of VocabRepository.swift so both clients share the same schema.
 */
object VocabRepository {
    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()
    private val storage: FirebaseStorage get() = FirebaseStorage.getInstance()

    fun userDoc(uid: String): DocumentReference = db.collection("users").document(uid)

    private fun listsRef(uid: String) = userDoc(uid).collection("lists")
    private fun wordsRef(uid: String, listId: String) = listsRef(uid).document(listId).collection("words")
    private fun dailyStatsRef(uid: String) = userDoc(uid).collection("dailyStats")

    /** Whether the given invitation code exists (registration gate). */
    suspend fun isValidInvitationCode(code: String): Boolean {
        val trimmed = code.trim()
        if (trimmed.isEmpty()) return false
        return try {
            db.collection("invitationCodes").document(trimmed).get().await().exists()
        } catch (e: Exception) {
            false
        }
    }

    // MARK: - Daily stats

    /** "yyyy-MM-dd" key in the device's calendar, used for daily-stat documents. */
    private val dayKeyFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    fun dayKey(date: Date): String = dayKeyFormatter.format(date)

    /** Increments today's remembered count for the given aspect. */
    suspend fun recordRemembered(uid: String, aspect: String, date: Date = Date()) {
        val field = when (aspect) {
            "spelling" -> "word"
            "translation" -> "translation"
            "pronunciation" -> "pronunciation"
            else -> return
        }
        val key = dayKey(date)
        dailyStatsRef(uid).document(key).set(
            mapOf("date" to key, field to FieldValue.increment(1)),
            com.google.firebase.firestore.SetOptions.merge()
        ).await()
    }

    /** Most recent `days` daily-stat documents (chronological order). */
    suspend fun fetchDailyStats(uid: String, days: Int): List<DailyStat> {
        val snapshot = dailyStatsRef(uid)
            .orderBy("date", Query.Direction.DESCENDING)
            .limit(days.toLong())
            .get().await()
        return snapshot.documents.mapNotNull { it.toObject(DailyStat::class.java) }
            .sortedBy { it.date }
    }

    // MARK: - Lists

    /** A stable per-list identifier: a 64-char SHA-256 hex string. */
    fun generateListPublicId(): String {
        val seed = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val digest = MessageDigest.getInstance("SHA-256").digest(seed)
        return digest.joinToString("") { "%02x".format(it) }
    }

    /** Ensures each list has a publicId, generating and persisting any missing one. */
    private suspend fun backfillPublicIds(uid: String, lists: MutableList<VocabularyList>) {
        for (i in lists.indices) {
            if (!lists[i].publicId.isNullOrEmpty()) continue
            val id = lists[i].id ?: continue
            val publicId = generateListPublicId()
            lists[i] = lists[i].copy(publicId = publicId)
            try {
                listsRef(uid).document(id).update("publicId", publicId).await()
            } catch (_: Exception) { /* best-effort */ }
        }
    }

    /** Active (non-trashed) lists, newest first. */
    suspend fun fetchLists(uid: String): List<VocabularyList> {
        val snapshot = listsRef(uid)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .get().await()
        val lists = snapshot.documents
            .mapNotNull { it.toObject(VocabularyList::class.java) }
            .filter { it.deletedAt == null }
            .toMutableList()
        backfillPublicIds(uid, lists)
        return lists
    }

    /** Lists currently in the trash, most recently deleted first. */
    suspend fun fetchTrashedLists(uid: String): List<VocabularyList> {
        val snapshot = listsRef(uid).get().await()
        val lists = snapshot.documents
            .mapNotNull { it.toObject(VocabularyList::class.java) }
            .filter { it.deletedAt != null }
            .sortedByDescending { it.deletedAt?.time ?: Long.MIN_VALUE }
            .toMutableList()
        backfillPublicIds(uid, lists)
        return lists
    }

    suspend fun createList(uid: String, name: String, learningLanguage: String, originalLanguage: String): String {
        val list = VocabularyList(
            name = name,
            createdAt = Date(),
            wordCount = 0,
            learningLanguage = learningLanguage,
            originalLanguage = originalLanguage,
            publicId = generateListPublicId(),
        )
        val ref = listsRef(uid).add(list).await()
        return ref.id
    }

    suspend fun renameList(uid: String, listId: String, name: String) {
        listsRef(uid).document(listId).update("name", name).await()
    }

    suspend fun setListTTS(uid: String, listId: String, enabled: Boolean) {
        listsRef(uid).document(listId).update("ttsEnabled", enabled).await()
    }

    /** Finds any user's list by its shared publicId and returns it with its words. */
    suspend fun fetchSharedList(publicId: String): SharedList? {
        val trimmed = publicId.trim()
        if (trimmed.isEmpty()) return null
        val snapshot = db.collectionGroup("lists")
            .whereEqualTo("publicId", trimmed)
            .limit(1)
            .get().await()
        val doc = snapshot.documents.firstOrNull() ?: return null
        val list = doc.toObject(VocabularyList::class.java) ?: return null
        val wordsSnapshot = doc.reference.collection("words").get().await()
        val words = wordsSnapshot.documents.mapNotNull { it.toObject(VocabWord::class.java) }
        return SharedList(list, words)
    }

    /** Soft-delete: move a list to the trash by stamping deletedAt. */
    suspend fun trashList(uid: String, listId: String) {
        listsRef(uid).document(listId).update("deletedAt", FieldValue.serverTimestamp()).await()
    }

    /** Restore a trashed list by clearing its deletedAt stamp. */
    suspend fun restoreList(uid: String, listId: String) {
        listsRef(uid).document(listId).update("deletedAt", FieldValue.delete()).await()
    }

    /** Permanently delete a list, its words, and any pronunciation audio. */
    suspend fun purgeList(uid: String, listId: String) {
        val words = wordsRef(uid, listId).get().await()
        // Only a word with a recording has anything in Storage, and those
        // deletes don't have to wait on each other — emptying the Trash of a
        // list that never had audio now costs no Storage requests at all.
        coroutineScope {
            words.documents
                .mapNotNull { it.getString("audioPath") }
                .filter { it.isNotEmpty() }
                .map { path -> async { deleteAudio(path) } }
                .awaitAll()
        }
        deleteDocuments(words.documents.map { it.reference }, listsRef(uid).document(listId))
    }

    /**
     * The most documents one delete batch holds: a batch takes 500 operations,
     * and the last one here spends its 500th on the parent document.
     */
    private const val DELETE_BATCH_LIMIT = 499

    /**
     * Deletes many documents in batches — emptying the Trash of a long list is
     * one round trip per 499 documents instead of one per document. [parent]
     * (the list itself) goes last, in the final batch, so a failure part-way
     * through leaves it in the Trash to be purged again rather than orphaning
     * the documents still under it.
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

    // MARK: - Words

    suspend fun fetchWords(uid: String, listId: String): List<VocabWord> {
        val snapshot = wordsRef(uid, listId)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .get().await()
        return snapshot.documents.mapNotNull { it.toObject(VocabWord::class.java) }
    }

    suspend fun addWord(uid: String, listId: String, word: VocabWord, audioFile: File? = null) {
        val ref = wordsRef(uid, listId).document()
        val toSave = word.copy(id = null)
        if (audioFile != null) {
            val path = audioStoragePath(uid, listId, ref.id)
            uploadAudio(audioFile, path)
            toSave.audioPath = path
        }
        ref.set(toSave).await()
        listsRef(uid).document(listId).update("wordCount", FieldValue.increment(1)).await()
    }

    /**
     * The most words one batch writes. A batch takes 500 operations, and each
     * one here spends its last on the list's word count.
     */
    private const val WORD_BATCH_LIMIT = 499

    /**
     * Writes many words at once, for the import flows. Storing them in batches
     * costs one round trip per 499 words instead of two per word, and each
     * batch either lands whole or not at all. Imported words never carry audio,
     * so there's nothing to upload alongside them.
     */
    suspend fun addWords(uid: String, listId: String, words: List<VocabWord>) {
        for (chunk in words.chunked(WORD_BATCH_LIMIT)) {
            val batch = db.batch()
            for (word in chunk) batch.set(wordsRef(uid, listId).document(), word.copy(id = null))
            batch.update(listsRef(uid).document(listId), "wordCount", FieldValue.increment(chunk.size.toLong()))
            batch.commit().await()
        }
    }

    /**
     * Updates a word. Pass [newAudioFile] to (re)upload a recording, or
     * [removeAudio] to delete the existing recording. With neither, the existing
     * audioPath is preserved.
     */
    suspend fun updateWord(
        uid: String,
        listId: String,
        word: VocabWord,
        newAudioFile: File? = null,
        removeAudio: Boolean = false,
        ttsEnabled: Boolean = false,
    ) {
        val id = word.id ?: return
        val path = audioStoragePath(uid, listId, id)
        if (newAudioFile != null) {
            uploadAudio(newAudioFile, path)
            word.audioPath = path
            word.refreshMemorization(ttsEnabled)
        } else if (removeAudio) {
            deleteAudio(path)
            word.audioPath = null
            word.refreshMemorization(ttsEnabled)
        }
        // Full overwrite (no merge) so a cleared audioPath is actually removed.
        // Null the @DocumentId field so it isn't written into the document body.
        wordsRef(uid, listId).document(id).set(word.copy(id = null)).await()
    }

    suspend fun deleteWord(uid: String, listId: String, wordId: String) {
        deleteAudio(audioStoragePath(uid, listId, wordId))
        wordsRef(uid, listId).document(wordId).delete().await()
        listsRef(uid).document(listId).update("wordCount", FieldValue.increment(-1)).await()
    }

    /** Moves a word between lists, preserving fields, progress and audio. */
    suspend fun moveWord(uid: String, fromListId: String, toListId: String, word: VocabWord) {
        val wordId = word.id ?: return
        if (fromListId == toListId) return

        val newWord = word.copy(id = null, audioPath = null)

        var localAudio: File? = null
        word.audioPath?.let { audioPath ->
            val data = downloadAudioData(audioPath)
            val tmp = File.createTempFile("retainic-move-", ".m4a")
            tmp.writeBytes(data)
            localAudio = tmp
        }

        addWord(uid, toListId, newWord, localAudio)
        localAudio?.delete()
        deleteWord(uid, fromListId, wordId)
    }

    // MARK: - Pronunciation audio (Firebase Storage)

    fun audioStoragePath(uid: String, listId: String, wordId: String): String =
        "users/$uid/lists/$listId/words/$wordId/pronunciation.m4a"

    private suspend fun uploadAudio(localFile: File, path: String) {
        val metadata = StorageMetadata.Builder()
            .setContentType("audio/mp4")
            .setCacheControl("public, max-age=604800")
            .build()
        storage.reference.child(path).putFile(Uri.fromFile(localFile), metadata).await()
    }

    suspend fun downloadAudioData(path: String): ByteArray =
        storage.reference.child(path).getBytes(10L * 1024 * 1024).await()

    private suspend fun deleteAudio(path: String) {
        try {
            storage.reference.child(path).delete().await()
        } catch (_: Exception) { /* ignore missing audio */ }
    }
}
