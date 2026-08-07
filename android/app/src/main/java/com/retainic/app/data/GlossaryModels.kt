package com.retainic.app.data

import com.google.firebase.firestore.DocumentId
import com.google.firebase.firestore.Exclude
import com.google.firebase.firestore.IgnoreExtraProperties
import java.util.Date

/**
 * Glossary models, ported from the iOS app's GlossaryModels.swift.
 *
 * A glossary is a single-language reference deck: each entry is a term and its
 * definition. Glossaries are independent of vocabulary lists — their own
 * documents, screens and practice — but they run on the same spaced-repetition
 * schedule as words, with two methods instead of three: recalling the term and
 * recalling the definition. There is no audio and no translation language, so
 * the pronunciation method never applies.
 *
 * Layout:
 *   users/{uid}/glossaries/{glossaryId}                   -> Glossary
 *   users/{uid}/glossaries/{glossaryId}/entries/{entryId} -> GlossaryEntry
 */

/** A named glossary (reference deck) owned by a user. */
@IgnoreExtraProperties
data class Glossary(
    @DocumentId var id: String? = null,
    var name: String = "",
    var createdAt: Date? = null,
    var entryCount: Int = 0,
    /** The one language its terms and definitions are written in. */
    var language: String? = null,
    /** When the glossary was moved to the trash, or null if it's active. */
    var deletedAt: Date? = null,
)

/** The two things a glossary entry is practised on. */
enum class GlossaryAspect(val raw: String, val dailyAspect: String) {
    /** Recalling the term itself; tallied with the word aspect in Statistics. */
    TERM("term", "spelling"),

    /** Recalling what the term means; tallied with the translation aspect. */
    DEFINITION("definition", "translation"),
}

/** An entry paired with the glossary it belongs to, for practice sessions. */
data class GlossaryPracticeCard(
    var entry: GlossaryEntry,
    val glossaryId: String,
)

/** A single term inside a glossary. */
@IgnoreExtraProperties
data class GlossaryEntry(
    @DocumentId var id: String? = null,
    var term: String = "",
    var definition: String = "",
    var notes: String = "",
    /** Per-aspect memory stats keyed "term"/"definition". */
    var memoryStats: Map<String, MemoryStat>? = null,
    var createdAt: Date? = null,

    var lastReviewed: Date? = null,
    var lastTermRemembered: Date? = null,
    var lastDefinitionRemembered: Date? = null,
    var timesSeen: Int = 0,
    var timesTermCorrect: Int? = 0,
    var timesDefinitionCorrect: Int? = 0,
    var remember_final: Boolean? = false,
) {
    /** Non-optional identifier for use as a list/selection key. */
    @get:Exclude
    val idValue: String get() = id ?: ""

    /** Whether the entry is fully remembered (the remember_final flag). */
    @get:Exclude
    val isRemembered: Boolean get() = remember_final == true

    fun isTermDue(now: Date = Date()): Boolean =
        isDue(timesTermCorrect ?: 0, lastTermRemembered, termReviewGaps, now)

    fun isDefinitionDue(now: Date = Date()): Boolean =
        isDue(timesDefinitionCorrect ?: 0, lastDefinitionRemembered, definitionReviewGaps, now)

    fun isDue(aspect: GlossaryAspect, now: Date = Date()): Boolean = when (aspect) {
        GlossaryAspect.TERM -> isTermDue(now)
        GlossaryAspect.DEFINITION -> isDefinitionDue(now)
    }

    /** Records a correct recall for the given method. */
    fun markCorrect(aspect: GlossaryAspect) {
        val now = Date()
        timesSeen += 1
        when (aspect) {
            GlossaryAspect.TERM -> { timesTermCorrect = (timesTermCorrect ?: 0) + 1; lastTermRemembered = now }
            GlossaryAspect.DEFINITION -> { timesDefinitionCorrect = (timesDefinitionCorrect ?: 0) + 1; lastDefinitionRemembered = now }
        }
        updateRememberFinal()
        lastReviewed = now
        record(aspect, correct = true, now)
    }

    fun markIncorrect(aspect: GlossaryAspect) {
        timesSeen += 1
        lastReviewed = Date()
        record(aspect, correct = false, Date())
    }

    /** Resets all review progress so the entry counts as never remembered. */
    fun resetMemory() {
        lastReviewed = null
        lastTermRemembered = null
        lastDefinitionRemembered = null
        timesSeen = 0
        timesTermCorrect = 0
        timesDefinitionCorrect = 0
        memoryStats = null
        remember_final = false
    }

    /**
     * An entry is memorized once both methods have run their schedules out:
     * 8x term and 10x definition. Entries carry no audio, so the pronunciation
     * requirement words can have never applies here.
     */
    private fun updateRememberFinal() {
        remember_final = (timesTermCorrect ?: 0) >= termReviewGaps.size &&
            (timesDefinitionCorrect ?: 0) >= definitionReviewGaps.size
    }

    private fun record(aspect: GlossaryAspect, correct: Boolean, now: Date) {
        val stats = (memoryStats ?: emptyMap()).toMutableMap()
        val stat = stats[aspect.raw] ?: MemoryStat()
        stat.seen += 1
        if (correct) {
            stat.timesRemembered += 1
            stat.lastRemembered = now
        }
        stats[aspect.raw] = stat
        memoryStats = stats
    }

    companion object {
        /** The term side follows the word (spelling) schedule... */
        val termReviewGaps = VocabWord.wordReviewGaps
        /** ...and the definition side the translation schedule. */
        val definitionReviewGaps = VocabWord.translationReviewGaps

        private fun isDue(count: Int, last: Date?, gaps: IntArray, now: Date): Boolean {
            if (count >= gaps.size) return false
            if (last == null) return true
            val days = VocabWord.daysBetween(VocabWord.startOfDay(last), VocabWord.startOfDay(now))
            return days >= gaps[count]
        }
    }
}
