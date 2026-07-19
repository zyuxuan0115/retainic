package com.retainic.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.viewmodel.compose.viewModel
import com.retainic.app.data.AuthService
import com.retainic.app.i18n.LocaleUtil
import com.retainic.app.i18n.Prefs
import com.retainic.app.ui.RootView
import com.retainic.app.ui.theme.RetainicTheme

/** The current interface-language code, available to every composable. */
val LocalAppLanguage = staticCompositionLocalOf { "en" }

/** Changes the interface language: persists it and recreates the activity. */
val LocalSetAppLanguage = staticCompositionLocalOf<(String) -> Unit> { {} }

class MainActivity : ComponentActivity() {

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleUtil.wrap(newBase, Prefs.preferredLanguage(newBase)))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val auth: AuthService = viewModel()
            val current = Prefs.preferredLanguage(this)
            CompositionLocalProvider(
                LocalAppLanguage provides current,
                LocalSetAppLanguage provides { code ->
                    Prefs.setPreferredLanguage(this, code)
                    recreate()
                },
            ) {
                RetainicTheme {
                    RootView(auth)
                }
            }
        }
    }
}
