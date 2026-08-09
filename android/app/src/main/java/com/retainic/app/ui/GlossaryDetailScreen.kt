package com.retainic.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.PlaylistAddCheck
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.Glossary
import com.retainic.app.data.GlossaryEntry
import com.retainic.app.data.GlossaryPracticeCard
import com.retainic.app.data.GlossaryRepository
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlossaryDetailScreen(
    auth: AuthService,
    glossary: Glossary,
    nav: GlossariesNav,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val glossaryId = glossary.id ?: ""
    val language = glossary.language ?: ""

    val entries = remember { mutableStateListOf<GlossaryEntry>() }
    var isLoading by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var glossaryName by remember { mutableStateOf(glossary.name) }
    var searchText by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(WordFilter.ALL) }

    var selecting by remember { mutableStateOf(false) }
    val selection = remember { mutableStateListOf<String>() }

    var showSettings by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<List<GlossaryEntry>>(emptyList()) }
    var pendingDeleteIsSelection by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    suspend fun load() {
        val uid = auth.uid ?: return
        isLoading = true
        try {
            entries.clear()
            entries.addAll(GlossaryRepository.fetchEntries(uid, glossaryId))
        } catch (e: Exception) {
            error = e.localizedMessage
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(auth.uid, glossaryId) { load() }

    val filtered = entries.filter { entry ->
        (when (filter) {
            WordFilter.ALL -> true
            WordFilter.REMEMBERED -> entry.isRemembered
            WordFilter.UNREMEMBERED -> !entry.isRemembered
        }) && (searchText.isEmpty() ||
            entry.term.contains(searchText, ignoreCase = true) ||
            entry.definitionTexts.any { it.contains(searchText, ignoreCase = true) })
    }

    fun endSelection() { selecting = false; selection.clear() }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (selecting) {
                            if (selection.isEmpty()) stringResource(R.string.select_terms)
                            else stringResource(R.string.n_selected, selection.size)
                        } else glossaryName
                    )
                },
                navigationIcon = {
                    if (selecting) {
                        IconButton(onClick = { endSelection() }) {
                            Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.done))
                        }
                    } else {
                        IconButton(onClick = { nav.pop() }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        }
                    }
                },
                actions = {
                    if (!selecting && entries.isNotEmpty()) {
                        IconButton(onClick = { selecting = true; selection.clear() }) {
                            Icon(Icons.AutoMirrored.Filled.PlaylistAddCheck,
                                contentDescription = stringResource(R.string.select))
                        }
                    }
                },
            )
        },
        bottomBar = {
            BottomAppBar {
                if (selecting) {
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = {
                            pendingDelete = entries.filter { selection.contains(it.id ?: "") }
                            pendingDeleteIsSelection = true
                            showDeleteConfirm = true
                        },
                        enabled = selection.isNotEmpty() && !isBusy,
                    ) {
                        Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(4.dp))
                        Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                    }
                    Spacer(Modifier.width(8.dp))
                } else {
                    if (entries.isNotEmpty()) {
                        TextButton(onClick = {
                            val cards = entries.map { GlossaryPracticeCard(it, glossaryId) }
                            nav.push(GlossariesRoute.Practice(cards))
                        }) {
                            Icon(Icons.Outlined.Style, contentDescription = null)
                            Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.practice))
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.glossary_settings))
                    }
                    IconButton(onClick = { nav.push(GlossariesRoute.Editor(glossaryId, language, null)) }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_term))
                    }
                }
            }
        },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                isLoading && entries.isEmpty() -> LoadingView(stringResource(R.string.loading))
                entries.isEmpty() -> EmptyState(
                    icon = Icons.AutoMirrored.Filled.MenuBook,
                    title = stringResource(R.string.no_terms_yet),
                    description = stringResource(R.string.add_terms_to_glossary, glossaryName),
                    actionLabel = stringResource(R.string.add_first_term),
                    onAction = { nav.push(GlossariesRoute.Editor(glossaryId, language, null)) },
                )
                else -> Column(Modifier.fillMaxSize()) {
                    OutlinedTextField(
                        searchText, { searchText = it },
                        placeholder = { Text(stringResource(R.string.search_terms)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(filtered, key = { it.idValue }) { entry ->
                            GlossaryEntryRow(
                                entry = entry,
                                selecting = selecting,
                                selected = selection.contains(entry.id ?: ""),
                                onClick = {
                                    if (selecting) {
                                        val id = entry.id ?: return@GlossaryEntryRow
                                        if (selection.contains(id)) selection.remove(id) else selection.add(id)
                                    } else {
                                        nav.push(GlossariesRoute.Editor(glossaryId, language, entry))
                                    }
                                },
                            )
                            RowDivider()
                        }
                    }
                }
            }
        }
    }

    // Delete confirmation
    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false; pendingDelete = emptyList() },
            title = {
                Text(
                    if (pendingDelete.size == 1) stringResource(R.string.delete_this_term)
                    else stringResource(R.string.delete_n_terms, pendingDelete.size)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    val toDelete = pendingDelete
                    val wasSelection = pendingDeleteIsSelection
                    pendingDelete = emptyList()
                    val uid = auth.uid ?: return@TextButton
                    scope.launch {
                        for (entry in toDelete) {
                            val id = entry.id ?: continue
                            try {
                                GlossaryRepository.deleteEntry(uid, glossaryId, id)
                                entries.removeAll { it.id == id }
                            } catch (e: Exception) { error = e.localizedMessage }
                        }
                        if (wasSelection) endSelection()
                    }
                }) { Text(stringResource(R.string.delete)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false; pendingDelete = emptyList() }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }

    if (showSettings) {
        GlossarySettingsDialog(
            initialName = glossaryName,
            filter = filter,
            onFilterChange = { filter = it },
            onDismiss = { showSettings = false },
            onSave = { newName ->
                val trimmed = newName.trim()
                if (trimmed.isNotEmpty()) {
                    glossaryName = trimmed
                    val uid = auth.uid
                    if (uid != null) scope.launch {
                        try { GlossaryRepository.renameGlossary(uid, glossaryId, trimmed) }
                        catch (e: Exception) { error = e.localizedMessage }
                    }
                }
                showSettings = false
            },
            onResetMemory = {
                showSettings = false
                val uid = auth.uid
                if (uid != null) scope.launch {
                    isBusy = true
                    try {
                        for (entry in entries) {
                            entry.resetMemory()
                            GlossaryRepository.updateEntry(uid, glossaryId, entry)
                        }
                    } catch (e: Exception) { error = e.localizedMessage }
                    isBusy = false
                }
            },
        )
    }

    ErrorDialog(error) { error = null }
}

/** One term and its definition in the glossary list. */
@Composable
private fun GlossaryEntryRow(
    entry: GlossaryEntry,
    selecting: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selecting) {
            Checkbox(checked = selected, onCheckedChange = { onClick() })
            Spacer(Modifier.width(8.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(entry.term, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(entry.joinedDefinitions, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
        }
    }
}

/** Per-glossary settings: rename it and reset every term's remembered state. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GlossarySettingsDialog(
    initialName: String,
    filter: WordFilter,
    onFilterChange: (WordFilter) -> Unit,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
    onResetMemory: () -> Unit,
) {
    var name by remember { mutableStateOf(initialName) }
    var showResetConfirm by remember { mutableStateOf(false) }
    val canSave = name.trim().isNotEmpty() && name.trim() != initialName.trim()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.glossary_settings)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = stringResource(R.string.cancel))
                        }
                    },
                    actions = {
                        IconButton(onClick = { onSave(name) }, enabled = canSave) {
                            Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.save))
                        }
                    },
                )
            },
        ) { inner ->
            Column(
                Modifier.padding(inner).fillMaxSize().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                OutlinedTextField(name, { name = it },
                    label = { Text(stringResource(R.string.glossary_name)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())

                Text(stringResource(R.string.show_terms), style = MaterialTheme.typography.titleSmall)
                WordFilter.entries.forEach { option ->
                    Row(Modifier.fillMaxWidth().clickable { onFilterChange(option) },
                        verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = filter == option, onClick = { onFilterChange(option) })
                        Text(stringResource(option.labelRes))
                    }
                }

                HorizontalDivider()
                TextButton(onClick = { showResetConfirm = true }) {
                    Text(stringResource(R.string.mark_all_not_remembered), color = MaterialTheme.colorScheme.error)
                }
                Text(stringResource(R.string.mark_all_terms_not_remembered_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text(stringResource(R.string.mark_all_terms_not_remembered_title)) },
            confirmButton = {
                TextButton(onClick = { showResetConfirm = false; onResetMemory() }) {
                    Text(stringResource(R.string.mark_all_not_remembered_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { showResetConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}
