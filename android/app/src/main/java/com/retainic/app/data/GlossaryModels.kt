package com.retainic.app.data

import com.google.firebase.firestore.DocumentId
import com.google.firebase.firestore.Exclude
import com.google.firebase.firestore.IgnoreExtraProperties
import java.util.Date

/**
 * Glossary models, ported from the iOS app's GlossaryModels.swift.
 *
 * A glossary is a single-language reference deck: each entry is a term and its
 * definitions. Glossaries are independent of vocabulary lists — their own
 * documents, screens and practice — and they run on the same spaced-repetition
 * machinery as words but with a schedule of their own: two methods instead of
 * three — recalling the term and recalling the definition — each finished after
 * five correct recalls. There is no audio and no translation language, so the
 * pronunciation method never applies.
 *
 * A term can mean several things, so an entry carries a list of definitions,
 * each with its own schedule: shown a definition, you recall the term, and
 * every definition is a card of its own. The other direction — shown the term,
 * recall what it means — stays one card that reveals them all.
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

/** One of the things a term means, with the review progress of its own card. */
@IgnoreExtraProperties
data class GlossaryDefinition(
    var text: String = "",
    var timesCorrect: Int = 0,
    var lastRemembered: Date? = null,
)

/** A single term inside a glossary. */
@IgnoreExtraProperties
data class GlossaryEntry(
    @DocumentId var id: String? = null,
    var term: String = "",
    /**
     * Everything the term means, each definition scheduled separately. Null or
     * empty on entries written before a term could mean several things, which
     * store the one meaning in [definition] instead.
     */
    var definitions: List<GlossaryDefinition>? = null,
    /**
     * The definitions as one line. Kept in step with [definitions] so clients
     * that only know about a single definition still read something coherent.
     */
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

    /**
     * The entry's definitions, each with its own schedule. An entry written
     * before a term could mean several things reads as a single definition
     * carrying the entry's definition counters.
     */
    @get:Exclude
    val definitionList: List<GlossaryDefinition>
        get() {
            val stored = definitions
            if (!stored.isNullOrEmpty()) return stored
            if (definition.isEmpty()) return emptyList()
            return listOf(
                GlossaryDefinition(definition, timesDefinitionCorrect ?: 0, lastDefinitionRemembered),
            )
        }

    /** Just the text of each definition, for display and search. */
    @get:Exclude
    val definitionTexts: List<String> get() = definitionList.map { it.text }

    /** The definitions as one line, for list rows and the legacy single field. */
    @get:Exclude
    val joinedDefinitions: String get() = definitionTexts.joinToString("; ")

    fun isTermDue(now: Date = Date()): Boolean =
        isDue(timesTermCorrect ?: 0, lastTermRemembered, reviewGaps, now)

    /** Whether a definition is due. With no [index], whether any is. */
    fun isDefinitionDue(now: Date = Date(), index: Int? = null): Boolean {
        val list = definitionList
        fun due(i: Int) = isDue(list[i].timesCorrect, list[i].lastRemembered, reviewGaps, now)
        if (index != null) return if (index in list.indices) due(index) else false
        return list.indices.any { due(it) }
    }

    /** The positions of the definitions due for review right now. */
    fun dueDefinitionIndexes(now: Date = Date()): List<Int> =
        definitionList.indices.filter { isDefinitionDue(now, it) }

    fun isDue(aspect: GlossaryAspect, now: Date = Date(), definitionIndex: Int? = null): Boolean = when (aspect) {
        GlossaryAspect.TERM -> isTermDue(now)
        GlossaryAspect.DEFINITION -> isDefinitionDue(now, definitionIndex)
    }

    /**
     * Records a correct recall for the given method. A definition recall
     * advances only the definition that was practised.
     */
    fun markCorrect(aspect: GlossaryAspect, definitionIndex: Int = 0) {
        val now = Date()
        timesSeen += 1
        when (aspect) {
            GlossaryAspect.TERM -> { timesTermCorrect = (timesTermCorrect ?: 0) + 1; lastTermRemembered = now }
            GlossaryAspect.DEFINITION -> {
                val list = definitionList.map { it.copy() }
                list.getOrNull(definitionIndex)?.let {
                    it.timesCorrect += 1
                    it.lastRemembered = now
                }
                definitions = list
                syncDefinitionFields()
            }
        }
        updateRememberFinal()
        lastReviewed = now
        record(aspect, correct = true, now)
    }

    /**
     * Replaces the entry's definitions with [texts], keeping the review
     * progress at each position: editing the wording of a definition leaves its
     * schedule alone, a new one starts unlearned, and a removed one takes its
     * progress with it.
     *
     * Not named `setDefinitions` (as it is on the other clients): that is the
     * JVM signature of the [definitions] property's own setter.
     */
    fun replaceDefinitions(texts: List<String>) {
        val previous = definitionList
        definitions = texts.mapIndexed { index, text ->
            val old = previous.getOrNull(index)
            GlossaryDefinition(text, old?.timesCorrect ?: 0, old?.lastRemembered)
        }
        syncDefinitionFields()
        updateRememberFinal()
    }

    /**
     * Mirrors the definition list onto the fields that predate it: the joined
     * text, the lowest per-definition count (what mastery waits on), and the
     * most recent recall (what Statistics counts).
     */
    private fun syncDefinitionFields() {
        val list = definitionList
        definition = list.joinToString("; ") { it.text }
        timesDefinitionCorrect = list.minOfOrNull { it.timesCorrect } ?: 0
        lastDefinitionRemembered = list.mapNotNull { it.lastRemembered }.maxByOrNull { it.time }
    }

    fun markIncorrect(aspect: GlossaryAspect) {
        timesSeen += 1
        lastReviewed = Date()
        record(aspect, correct = false, Date())
    }

    /** Resets all review progress so the entry counts as never remembered. */
    fun resetMemory() {
        definitions = definitionTexts.map { GlossaryDefinition(it) }
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
     * An entry is memorized once every side of it is finished: the term
     * recalled its five times, and each definition its own five. A term that
     * means five things isn't done until all five meanings are. Entries carry
     * no audio, so the pronunciation requirement words can have never applies.
     */
    private fun updateRememberFinal() {
        val list = definitionList
        remember_final = (timesTermCorrect ?: 0) >= requiredRecalls &&
            list.isNotEmpty() && list.all { it.timesCorrect >= requiredRecalls }
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
        /**
         * The glossary schedule. Glossaries review on their own gaps rather
         * than a word's: the term, and every one of its definitions, is
         * recalled five times. The value at index n is how many days to wait
         * after the nth correct recall; past the end of the table that side is
         * finished and never comes due again.
         */
        val reviewGaps = intArrayOf(0, 1, 1, 2, 4)

        /** How many correct recalls finish the term, and each definition. */
        val requiredRecalls: Int get() = reviewGaps.size

        private fun isDue(count: Int, last: Date?, gaps: IntArray, now: Date): Boolean {
            if (count >= gaps.size) return false
            if (last == null) return true
            val days = VocabWord.daysBetween(VocabWord.startOfDay(last), VocabWord.startOfDay(now))
            return days >= gaps[count]
        }
    }
}
