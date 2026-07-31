package com.retainic.app.data

import com.google.firebase.firestore.DocumentId
import com.google.firebase.firestore.Exclude
import com.google.firebase.firestore.IgnoreExtraProperties
import java.util.Calendar
import java.util.Date
import java.util.concurrent.TimeUnit

/**
 * Cloud (Firestore) data models. Ported from the iOS app's FirestoreModels.swift.
 *
 * Layout:
 *   users/{uid}                         -> UserProfile
 *   users/{uid}/lists/{listId}          -> VocabularyList
 *   users/{uid}/lists/{listId}/words/{} -> VocabWord
 *   users/{uid}/dailyStats/{yyyy-MM-dd} -> DailyStat
 *
 * Every class uses defaults for all fields so Firestore can instantiate it, and
 * `var` fields so older documents that omit a field still decode.
 */

/** Account profile created at registration. */
@IgnoreExtraProperties
data class UserProfile(
    var username: String = "",
    var email: String = "",
    var createdAt: Date? = null,
)

/** A named vocabulary list (deck) owned by a user. */
@IgnoreExtraProperties
data class VocabularyList(
    @DocumentId var id: String? = null,
    var name: String = "",
    var createdAt: Date? = null,
    var wordCount: Int = 0,
    var learningLanguage: String? = null,
    var originalLanguage: String? = null,
    /** When the list was moved to the trash, or null if it's active. */
    var deletedAt: Date? = null,
    /** Stable per-list identifier (64-char SHA-256 hex), independent of docID. */
    var publicId: String? = null,
    /** Fall back to synthesized speech for words without a recording. */
    var ttsEnabled: Boolean? = null,
)

/** A list found by its shared publicId, together with its words. */
data class SharedList(
    val list: VocabularyList,
    val words: List<VocabWord>,
)

/** Memory stats for one aspect of a word. Stored for analysis; not shown in UI. */
@IgnoreExtraProperties
data class MemoryStat(
    var seen: Int = 0,
    var timesRemembered: Int = 0,
    var lastRemembered: Date? = null,
)

/** A word paired with the list it belongs to, for practice sessions. */
data class PracticeCard(
    var word: VocabWord,
    val listId: String,
)

/** Daily tally of how many words were remembered per aspect. */
@IgnoreExtraProperties
data class DailyStat(
    @DocumentId var id: String? = null,
    var date: String = "",
    var word: Int? = null,
    var translation: Int? = null,
    var pronunciation: Int? = null,
)

/**
 * A single vocabulary entry inside a list. Field names match the iOS documents
 * exactly, including the historical misspellings "Pronounciation" and the
 * snake_case `remember_final`, so both clients read and write the same data.
 */
@IgnoreExtraProperties
data class VocabWord(
    @DocumentId var id: String? = null,
    var term: String = "",
    /** Legacy scalar, kept non-null so older app builds continue decoding. */
    var translation: String = "",
    /** Complete ordered fact list. Null so legacy documents still decode. */
    var translations: List<String>? = null,
    var notes: String = "",
    /** Parts of speech (raw values). A word may have several. */
    var partsOfSpeech: List<String>? = null,
    /** Legacy single part of speech, kept so older documents still decode. */
    var partOfSpeech: String? = null,
    var hiragana: String? = null,
    var pinyin: String? = null,
    /** Firebase Storage path of the pronunciation recording, if any. */
    var audioPath: String? = null,
    /** Per-aspect memory stats keyed "translation"/"pronunciation"/"spelling". */
    var memoryStats: Map<String, MemoryStat>? = null,
    var createdAt: Date? = null,

    var lastReviewed: Date? = null,
    var lastWordRemembered: Date? = null,
    var lastPronounciationRemembered: Date? = null,
    var lastTranslationRemembered: Date? = null,
    var timesSeen: Int = 0,
    var timesWordCorrect: Int? = 0,
    var timesPronounciationCorrect: Int? = 0,
    var timesTranslationCorrect: Int? = 0,
    var remember_final: Boolean? = false,
) {
    /** Non-optional identifier for use as a list/selection key. */
    @get:Exclude
    val idValue: String get() = id ?: ""

    /** Ordered facts, preferring the plural field and falling back to scalar. */
    @get:Exclude
    val translationValues: List<String>
        get() {
            val plural = translations.orEmpty().map { it.trim() }.filter { it.isNotEmpty() }
            if (plural.isNotEmpty()) return plural
            val legacy = translation.trim()
            return if (legacy.isEmpty()) emptyList() else listOf(legacy)
        }

    /** Every text fact available to prompt, with the studied term first. */
    @get:Exclude
    val factValues: List<String>
        get() = listOfNotNull(term.trim().takeIf { it.isNotEmpty() }) + translationValues

    /** Re-emits both document shapes before every write for old-client safety. */
    fun normalizeTranslationsForWrite() {
        val facts = translationValues
        if (facts.isNotEmpty()) {
            translation = facts.first()
            translations = facts
        }
    }

    /**
     * Selected parts of speech, reading the array field and falling back to the
     * legacy single value. Excludes UNSPECIFIED.
     */
    @get:Exclude
    val partOfSpeechValues: List<PartOfSpeech>
        get() {
            partsOfSpeech?.takeIf { it.isNotEmpty() }?.let { raw ->
                return raw.mapNotNull { PartOfSpeech.fromRaw(it) }.filter { it != PartOfSpeech.UNSPECIFIED }
            }
            partOfSpeech?.let { single ->
                PartOfSpeech.fromRaw(single)?.let { if (it != PartOfSpeech.UNSPECIFIED) return listOf(it) }
            }
            return emptyList()
        }

    /** Phonetic reading to display (hiragana or pinyin), if any. */
    @get:Exclude
    val reading: String?
        get() = listOf(hiragana, pinyin).firstOrNull { !it.isNullOrEmpty() }

    /** Whether the word is fully remembered (the remember_final flag). */
    @get:Exclude
    val isRemembered: Boolean get() = remember_final == true

    /** Whether the given memory aspect was recalled correctly today. */
    fun wasRememberedToday(aspect: String): Boolean {
        val last = memoryStats?.get(aspect)?.lastRemembered ?: return false
        return isSameDay(last, Date())
    }

    fun isTranslationDue(now: Date = Date()): Boolean =
        isDue(timesTranslationCorrect ?: 0, lastTranslationRemembered, translationReviewGaps, now)

    fun isWordDue(now: Date = Date()): Boolean =
        isDue(timesWordCorrect ?: 0, lastWordRemembered, wordReviewGaps, now)

    fun isPronunciationDue(now: Date = Date()): Boolean =
        isDue(timesPronounciationCorrect ?: 0, lastPronounciationRemembered, pronunciationReviewGaps, now)

    /**
     * Records a correct recall for the given aspect. Pass the list's ttsEnabled so
     * mastery is re-evaluated against the same pronunciation requirement.
     */
    fun markCorrect(aspect: String?, ttsEnabled: Boolean = false) {
        val now = Date()
        timesSeen += 1
        when (aspect) {
            "spelling" -> { timesWordCorrect = (timesWordCorrect ?: 0) + 1; lastWordRemembered = now }
            "pronunciation" -> { timesPronounciationCorrect = (timesPronounciationCorrect ?: 0) + 1; lastPronounciationRemembered = now }
            "translation" -> { timesTranslationCorrect = (timesTranslationCorrect ?: 0) + 1; lastTranslationRemembered = now }
        }
        updateRememberFinal(ttsEnabled)
        lastReviewed = now
        record(aspect, correct = true, now)
    }

    fun markIncorrect(aspect: String?) {
        timesSeen += 1
        lastReviewed = Date()
        record(aspect, correct = false, Date())
    }

    /** Resets all spaced-repetition progress so the word counts as never remembered. */
    fun resetMemory() {
        lastReviewed = null
        lastWordRemembered = null
        lastPronounciationRemembered = null
        lastTranslationRemembered = null
        timesSeen = 0
        timesWordCorrect = 0
        timesPronounciationCorrect = 0
        timesTranslationCorrect = 0
        memoryStats = null
    }

    /** Re-evaluates mastery after the pronunciation requirement may have changed. */
    fun refreshMemorization(ttsEnabled: Boolean = false) = updateRememberFinal(ttsEnabled)

    private fun updateRememberFinal(ttsEnabled: Boolean) {
        val word = timesWordCorrect ?: 0
        val translation = timesTranslationCorrect ?: 0
        val pronunciation = timesPronounciationCorrect ?: 0
        val pronunciationRequired = audioPath != null || ttsEnabled
        val pronunciationOK = !pronunciationRequired || pronunciation >= 7
        remember_final = word >= 8 && translation >= 10 && pronunciationOK
    }

    private fun record(aspect: String?, correct: Boolean, now: Date) {
        val a = aspect ?: return
        val stats = (memoryStats ?: emptyMap()).toMutableMap()
        val entry = stats[a] ?: MemoryStat()
        entry.seen += 1
        if (correct) {
            entry.timesRemembered += 1
            entry.lastRemembered = now
        }
        stats[a] = entry
        memoryStats = stats
    }

    companion object {
        /** Min days between translation reviews, indexed by remembered count. */
        val translationReviewGaps = intArrayOf(0, 1, 1, 1, 2, 2, 3, 4, 5, 10)
        /** Min days between word (spelling) reviews. */
        val wordReviewGaps = intArrayOf(0, 1, 1, 2, 3, 4, 6, 9)
        /** Min days between pronunciation reviews. */
        val pronunciationReviewGaps = intArrayOf(0, 1, 2, 3, 4, 6, 8)

        private fun isDue(count: Int, last: Date?, gaps: IntArray, now: Date): Boolean {
            if (count >= gaps.size) return false
            if (last == null) return true
            val days = daysBetween(startOfDay(last), startOfDay(now))
            return days >= gaps[count]
        }

        fun startOfDay(date: Date): Date {
            val cal = Calendar.getInstance()
            cal.time = date
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            return cal.time
        }

        fun daysBetween(from: Date, to: Date): Int =
            TimeUnit.MILLISECONDS.toDays(to.time - from.time).toInt()

        fun isSameDay(a: Date, b: Date): Boolean {
            val ca = Calendar.getInstance().apply { time = a }
            val cb = Calendar.getInstance().apply { time = b }
            return ca.get(Calendar.YEAR) == cb.get(Calendar.YEAR) &&
                ca.get(Calendar.DAY_OF_YEAR) == cb.get(Calendar.DAY_OF_YEAR)
        }
    }
}
