package com.retainic.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.retainic.app.LocalAppLanguage
import com.retainic.app.LocalSetAppLanguage
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.i18n.Language
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(auth: AuthService, modifier: Modifier = Modifier) {
    val current = LocalAppLanguage.current
    val setLang = LocalSetAppLanguage.current
    var showLangMenu by remember { mutableStateOf(false) }
    var showSignOut by remember { mutableStateOf(false) }
    var showChangePassword by remember { mutableStateOf(false) }

    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.settings)) }) },
    ) { inner ->
        Column(
            Modifier.padding(inner).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SectionHeader(stringResource(R.string.account))
            LabeledRow(stringResource(R.string.username), auth.profile?.username ?: auth.displayName ?: "—")
            LabeledRow(stringResource(R.string.email), auth.profile?.email ?: auth.email ?: "—")

            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SectionHeader(stringResource(R.string.language))
            Row(
                Modifier.fillMaxWidth().clickable { showLangMenu = true }.padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.preferred_language), Modifier.weight(1f))
                Text(Language.named(current)?.autonym ?: current, color = MaterialTheme.colorScheme.primary)
                DropdownMenu(expanded = showLangMenu, onDismissRequest = { showLangMenu = false }) {
                    Language.all.forEach { lang ->
                        DropdownMenuItem(text = { Text(lang.autonym) },
                            onClick = { showLangMenu = false; setLang(lang.code) })
                    }
                }
            }

            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            // A TextButton indents its label by its own content padding, which
            // left these two sitting to the right of every other row. Clearing
            // that padding and letting the label fill the width lines them up
            // with Account and Language, and gives them the same full-width
            // tap target as the language row.
            TextButton(
                onClick = { showChangePassword = true },
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(vertical = 12.dp),
            ) {
                Text(stringResource(R.string.change_password), Modifier.weight(1f))
            }
            TextButton(
                onClick = { showSignOut = true },
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(vertical = 12.dp),
            ) {
                Text(stringResource(R.string.sign_out), Modifier.weight(1f),
                    color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (showSignOut) {
        AlertDialog(
            onDismissRequest = { showSignOut = false },
            title = { Text(stringResource(R.string.sign_out_confirm)) },
            confirmButton = {
                TextButton(onClick = { showSignOut = false; auth.signOut() }) {
                    Text(stringResource(R.string.sign_out), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showSignOut = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    if (showChangePassword) {
        ChangePasswordDialog(auth) { showChangePassword = false }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary)
}

@Composable
private fun LabeledRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(label, Modifier.weight(1f))
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ChangePasswordDialog(auth: AuthService, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var current by remember { mutableStateOf("") }
    var new by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    remember { auth.errorMessage = null }

    val canSave = current.isNotEmpty() && new.length >= 6 && confirm == new && !auth.isWorking

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.change_password)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(current, { current = it }, label = { Text(stringResource(R.string.current_password)) },
                    singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(new, { new = it }, label = { Text(stringResource(R.string.new_password)) },
                    singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth())
                Text(stringResource(R.string.password_min), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(confirm, { confirm = it }, label = { Text(stringResource(R.string.confirm_new_password)) },
                    singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth())
                auth.errorMessage?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = canSave,
                onClick = {
                    scope.launch {
                        val ok = auth.changePassword(current, new)
                        if (ok) onDismiss()
                    }
                },
            ) { Text(stringResource(R.string.save)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
