package com.retainic.app.ui

import androidx.compose.runtime.Composable
import com.retainic.app.data.AuthService

/** Root gate: sign in -> main app. Mirrors ContentView.swift. */
@Composable
fun RootView(auth: AuthService) {
    if (!auth.isAuthenticated) {
        AuthScreen(auth)
    } else {
        MainScaffold(auth)
    }
}
