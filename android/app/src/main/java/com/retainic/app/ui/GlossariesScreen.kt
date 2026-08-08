package com.retainic.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.Glossary
import com.retainic.app.data.GlossaryRepository
import com.retainic.app.i18n.Language
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlossariesScreen(auth: AuthService, nav: GlossariesNav, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var glossaries by remember { mutableStateOf<List<Glossary>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showNewGlossary by remember { mutableStateOf(false) }
    var pendingTrash by remember { mutableStateOf<Glossary?>(null) }

    suspend fun load() {
        val uid = auth.uid ?: return
        isLoading = true
        try {
            glossaries = GlossaryRepository.fetchGlossaries(uid)
        } catch (e: Exception) {
            error = e.localizedMessage
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(auth.uid) { load() }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.glossaries)) },
                navigationIcon = {
                    IconButton(onClick = { nav.push(GlossariesRoute.Trash) }) {
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.trash))
                    }
                },
                actions = {
                    IconButton(onClick = { showNewGlossary = true }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.new_glossary))
                    }
                },
            )
        },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                isLoading && glossaries.isEmpty() -> LoadingView(stringResource(R.string.loading))
                glossaries.isEmpty() -> EmptyState(
                    icon = Icons.AutoMirrored.Filled.MenuBook,
                    title = stringResource(R.string.no_glossaries_yet),
                    description = stringResource(R.string.create_first_glossary),
                    actionLabel = stringResource(R.string.create_a_glossary),
                    onAction = { showNewGlossary = true },
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(glossaries, key = { it.id ?: it.name }) { glossary ->
                        val dismissState = rememberSwipeToDismissBoxState(
                            confirmValueChange = { value ->
                                if (value == SwipeToDismissBoxValue.EndToStart) pendingTrash = glossary
                                false // never auto-dismiss; the dialog performs the trash
                            },
                        )
                        SwipeToDismissBox(
                            state = dismissState,
                            enableDismissFromStartToEnd = false,
                            backgroundContent = {
                                Box(
                                    Modifier.fillMaxSize()
                                        .background(MaterialTheme.colorScheme.errorContainer)
                                        .padding(horizontal = 20.dp),
                                    contentAlignment = Alignment.CenterEnd,
                                ) {
                                    Icon(Icons.Filled.Delete, contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onErrorContainer)
                                }
                            },
                        ) {
                            GlossaryRow(glossary, Modifier.clickable { nav.push(GlossariesRoute.Detail(glossary)) })
                        }
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    if (showNewGlossary) {
        NewGlossaryDialog(
            onDismiss = { showNewGlossary = false },
            onCreate = { name, language ->
                showNewGlossary = false
                val uid = auth.uid ?: return@NewGlossaryDialog
                scope.launch {
                    try {
                        GlossaryRepository.createGlossary(uid, name.trim(), language)
                        load()
                    } catch (e: Exception) { error = e.localizedMessage }
                }
            },
        )
    }

    pendingTrash?.let { target ->
        AlertDialog(
            onDismissRequest = { pendingTrash = null },
            title = { Text(stringResource(R.string.move_to_trash)) },
            text = { Text(stringResource(R.string.glossary_will_move_trash, target.name)) },
            confirmButton = {
                TextButton(onClick = {
                    val uid = auth.uid
                    val id = target.id
                    pendingTrash = null
                    if (uid != null && id != null) scope.launch {
                        try {
                            GlossaryRepository.trashGlossary(uid, id)
                            glossaries = glossaries.filterNot { it.id == id }
                        } catch (e: Exception) { error = e.localizedMessage }
                    }
                }) { Text(stringResource(R.string.move_to_trash)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingTrash = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    ErrorDialog(error) { error = null }
}

@Composable
fun GlossaryRow(glossary: Glossary, modifier: Modifier = Modifier) {
    val preferred = LocalAppLanguage.current
    val language = glossary.language?.let { Language.named(it)?.displayName(preferred) }
    Row(
        modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.MenuBook, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary)
        Column {
            Text(glossary.name, style = MaterialTheme.typography.titleMedium)
            Text(
                listOfNotNull(stringResource(R.string.n_terms, glossary.entryCount), language).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Names a new glossary and picks the one language its terms are written in. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewGlossaryDialog(onDismiss: () -> Unit, onCreate: (String, String) -> Unit) {
    val preferred = LocalAppLanguage.current
    var name by remember { mutableStateOf("") }
    var language by remember { mutableStateOf(preferred) }
    val canCreate = name.trim().isNotEmpty() && language.isNotEmpty()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.new_glossary)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel))
                        }
                    },
                    actions = {
                        IconButton(onClick = { onCreate(name, language) }, enabled = canCreate) {
                            Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.create))
                        }
                    },
                )
            },
        ) { inner ->
            Column(
                Modifier.padding(inner).fillMaxSize().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                OutlinedTextField(
                    name, { name = it },
                    label = { Text(stringResource(R.string.glossary_name)) },
                    placeholder = { Text(stringResource(R.string.eg_legal_terms)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth(),
                )
                // A glossary is monolingual: terms and definitions are both
                // written in this one language, so there is no translation
                // language to pick.
                LanguageDropdown(stringResource(R.string.terms_are_in), language, preferred) { language = it }
                Text(stringResource(R.string.glossary_language_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
