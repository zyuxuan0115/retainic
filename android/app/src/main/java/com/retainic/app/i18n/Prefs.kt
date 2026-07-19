package com.retainic.app.i18n

import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import java.util.Locale

/** Persists the user-chosen interface language (overrides the device language). */
object Prefs {
    private const val FILE = "retainic"
    private const val KEY = "preferredLanguage"

    fun preferredLanguage(context: Context): String {
        val sp = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        return sp.getString(KEY, null) ?: Language.systemDefault()
    }

    fun setPreferredLanguage(context: Context, code: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putString(KEY, code).apply()
    }
}

/** Wraps a base context so resources resolve in the chosen interface language. */
object LocaleUtil {
    fun wrap(base: Context, code: String): Context {
        val locale = Locale.forLanguageTag(Language.localeTag(code))
        Locale.setDefault(locale)
        val config = base.resources.configuration
        config.setLocale(locale)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            base.createConfigurationContext(config)
        } else {
            @Suppress("DEPRECATION")
            base.resources.updateConfiguration(config, base.resources.displayMetrics)
            ContextWrapper(base)
        }
    }
}
