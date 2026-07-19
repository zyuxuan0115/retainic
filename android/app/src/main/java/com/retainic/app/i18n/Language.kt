package com.retainic.app.i18n

import java.util.Locale

/**
 * The curated set of interface / study languages. Ported from Language.swift.
 * Display names come from the JVM's locale data, matching the iOS behaviour of
 * rendering a language's name in the chosen UI language (or in itself).
 */
data class Language(val code: String, val name: String) {
    /** The language's name written in the given UI language code. */
    fun displayName(uiCode: String): String {
        val target = Locale.forLanguageTag(localeTag(code))
        val ui = Locale.forLanguageTag(localeTag(uiCode))
        val localized = target.getDisplayLanguage(ui)
        if (localized.isBlank()) return name
        return localized.replaceFirstChar { it.titlecase(ui) }
    }

    /** The language's name written in itself (its autonym), e.g. "Español". */
    val autonym: String get() = displayName(code)

    companion object {
        val all: List<Language> = listOf(
            Language("en", "English"),
            Language("es", "Spanish"),
            Language("zh", "Chinese"),
            Language("ja", "Japanese"),
            Language("ko", "Korean"),
        )

        fun named(code: String): Language? = all.firstOrNull { it.code == code }

        /** Maps an app language code to a BCP-47 tag for locale lookup. */
        fun localeTag(code: String): String = if (code == "zh") "zh-Hans" else code

        /** The best supported language for the device, defaulting to English. */
        fun systemDefault(): String {
            val code = Locale.getDefault().language
            return if (all.any { it.code == code }) code else "en"
        }
    }
}
