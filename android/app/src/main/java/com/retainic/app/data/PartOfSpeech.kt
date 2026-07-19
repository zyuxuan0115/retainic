package com.retainic.app.data

/**
 * Grammatical category of a word. Stored as a stable key; displayed with a label
 * localized to the user's native language. Ported from iOS PartOfSpeech.swift —
 * labels are a hardcoded per-language map (not Android string resources) so the
 * stored raw values and the labels match the other clients exactly.
 */
enum class PartOfSpeech(val raw: String) {
    UNSPECIFIED("unspecified"),
    NOUN("noun"),
    VERB("verb"),
    ADJECTIVE("adjective"),
    ADVERB("adverb"),
    PRONOUN("pronoun"),
    PREPOSITION("preposition"),
    CONJUNCTION("conjunction"),
    INTERJECTION("interjection");

    /** Localized label, keyed by native-language code. Falls back to English. */
    fun label(nativeCode: String): String {
        val table = labels[nativeCode] ?: labels["en"]!!
        return table[this] ?: raw.replaceFirstChar { it.uppercase() }
    }

    companion object {
        /** All cases except UNSPECIFIED, in declaration order (the selectable set). */
        val selectable: List<PartOfSpeech> = entries.filter { it != UNSPECIFIED }

        fun fromRaw(raw: String): PartOfSpeech? = entries.firstOrNull { it.raw == raw }

        private val labels: Map<String, Map<PartOfSpeech, String>> = mapOf(
            "en" to mapOf(
                UNSPECIFIED to "Unspecified", NOUN to "Noun", VERB to "Verb",
                ADJECTIVE to "Adjective", ADVERB to "Adverb", PRONOUN to "Pronoun",
                PREPOSITION to "Preposition", CONJUNCTION to "Conjunction", INTERJECTION to "Interjection",
            ),
            "es" to mapOf(
                UNSPECIFIED to "Sin especificar", NOUN to "Sustantivo", VERB to "Verbo",
                ADJECTIVE to "Adjetivo", ADVERB to "Adverbio", PRONOUN to "Pronombre",
                PREPOSITION to "Preposición", CONJUNCTION to "Conjunción", INTERJECTION to "Interjección",
            ),
            "zh" to mapOf(
                UNSPECIFIED to "未指定", NOUN to "名词", VERB to "动词",
                ADJECTIVE to "形容词", ADVERB to "副词", PRONOUN to "代词",
                PREPOSITION to "介词", CONJUNCTION to "连词", INTERJECTION to "感叹词",
            ),
            "ja" to mapOf(
                UNSPECIFIED to "指定なし", NOUN to "名詞", VERB to "動詞",
                ADJECTIVE to "形容詞", ADVERB to "副詞", PRONOUN to "代名詞",
                PREPOSITION to "前置詞", CONJUNCTION to "接続詞", INTERJECTION to "感動詞",
            ),
            "ko" to mapOf(
                UNSPECIFIED to "미지정", NOUN to "명사", VERB to "동사",
                ADJECTIVE to "형용사", ADVERB to "부사", PRONOUN to "대명사",
                PREPOSITION to "전치사", CONJUNCTION to "접속사", INTERJECTION to "감탄사",
            ),
        )
    }
}
