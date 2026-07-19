package com.retainic.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.retainic.app.LocalSetAppLanguage
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.i18n.Language

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthScreen(auth: AuthService) {
    var isRegistering by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var invitationCode by remember { mutableStateOf("") }
    var showLangMenu by remember { mutableStateOf(false) }
    val setLang = LocalSetAppLanguage.current

    val isValid = run {
        val emailOK = email.contains("@") && email.contains(".")
        val passwordOK = password.length >= 6
        val usernameOK = !isRegistering || username.trim().isNotEmpty()
        val inviteOK = !isRegistering || invitationCode.trim().isNotEmpty()
        emailOK && passwordOK && usernameOK && inviteOK
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(if (isRegistering) R.string.create_account else R.string.welcome_back)) },
                actions = {
                    IconButton(onClick = { showLangMenu = true }) {
                        Icon(Icons.Outlined.Language, contentDescription = stringResource(R.string.language))
                    }
                    DropdownMenu(expanded = showLangMenu, onDismissRequest = { showLangMenu = false }) {
                        Language.all.forEach { lang ->
                            DropdownMenuItem(
                                text = { Text(lang.autonym) },
                                onClick = { showLangMenu = false; setLang(lang.code) },
                            )
                        }
                    }
                },
            )
        },
    ) { inner ->
        Column(
            Modifier
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Icon(Icons.Filled.MenuBook, contentDescription = null, modifier = Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.primary)
            Text("Retainic", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.sign_in_subtitle), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)

            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = !isRegistering,
                    onClick = { isRegistering = false; auth.errorMessage = null },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                ) { Text(stringResource(R.string.log_in)) }
                SegmentedButton(
                    selected = isRegistering,
                    onClick = { isRegistering = true; auth.errorMessage = null },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                ) { Text(stringResource(R.string.register)) }
            }

            if (isRegistering) {
                OutlinedTextField(username, { username = it }, label = { Text(stringResource(R.string.username)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            OutlinedTextField(email, { email = it }, label = { Text(stringResource(R.string.email)) },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email))
            OutlinedTextField(password, { password = it }, label = { Text(stringResource(R.string.password)) },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
            if (isRegistering) {
                OutlinedTextField(invitationCode, { invitationCode = it },
                    label = { Text(stringResource(R.string.invitation_code)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
            }

            auth.errorMessage?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.fillMaxWidth())
            }

            Button(
                onClick = {
                    val e = email.trim()
                    if (isRegistering) {
                        auth.register(e, password, username.trim(), invitationCode.trim())
                    } else {
                        auth.signIn(e, password)
                    }
                },
                enabled = isValid && !auth.isWorking,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (auth.isWorking) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary)
                } else {
                    Text(stringResource(if (isRegistering) R.string.create_account else R.string.log_in))
                }
            }

            if (isRegistering) {
                Text(stringResource(R.string.password_min), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
