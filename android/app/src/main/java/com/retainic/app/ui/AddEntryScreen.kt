package com.retainic.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.GlossaryEntry
import com.retainic.app.data.GlossaryRepository
import com.retainic.app.i18n.Language
import kotlinx.coroutines.launch
import java.util.Date

/** Create a new term in a glossary, or edit an existing one. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddEntryScreen(
    auth: AuthService,
    glossaryId: String,
    language: String,
    existing: GlossaryEntry?,
    nav: GlossariesNav,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val preferred = LocalAppLanguage.current
    val isEditing = existing != null

    var term by remember { mutableStateOf(existing?.term ?: "") }
    // One field per definition — a term can mean several things, and each
    // meaning is practised on its own.
    val savedDefinitions = existing?.definitionTexts.orEmpty()
    val definitions = remember {
        mutableStateListOf<String>().apply { addAll(savedDefinitions.ifEmpty { listOf("") }) }
    }
    var notes by remember { mutableStateOf(existing?.notes ?: "") }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    // The definitions that would be saved: trimmed, with the blank fields dropped.
    val filledDefinitions = definitions.map { it.trim() }.filter { it.isNotEmpty() }

    // When editing, Save stays disabled until something actually changes.
    val hasChanges = if (existing == null) true else
        term.trim() != existing.term ||
            filledDefinitions != savedDefinitions ||
            notes.trim() != existing.notes
    val canSave = term.trim().isNotEmpty() && filledDefinitions.isNotEmpty() && !isSaving && hasChanges

    fun save() {
        val uid = auth.uid ?: return
        isSaving = true
        error = null
        scope.launch {
            try {
                if (existing != null) {
                    val updated = existing.copy(term = term.trim(), notes = notes.trim())
                    updated.setDefinitions(filledDefinitions)
                    GlossaryRepository.updateEntry(uid, glossaryId, updated)
                } else {
                    val entry = GlossaryEntry(term = term.trim(), notes = notes.trim(), createdAt = Date())
                    entry.setDefinitions(filledDefinitions)
                    GlossaryRepository.addEntry(uid, glossaryId, entry)
                }
                nav.pop()
            } catch (e: Exception) {
                error = e.localizedMessage
                isSaving = false
            }
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(if (isEditing) R.string.edit_term else R.string.new_term)) },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.cancel))
                    }
                },
                actions = {
                    IconButton(onClick = { save() }, enabled = canSave) {
                        Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.save))
                    }
                },
            )
        },
    ) { inner ->
        Column(
            Modifier.padding(inner).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SectionLabel(Language.named(language)?.displayName(preferred) ?: stringResource(R.string.term))
            OutlinedTextField(term, { term = it }, label = { Text(stringResource(R.string.term)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())

            SectionLabel(stringResource(R.string.definitions))
            definitions.forEachIndexed { index, value ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(value, { definitions[index] = it },
                        label = { Text(stringResource(R.string.what_it_means)) },
                        modifier = Modifier.weight(1f), minLines = 2, maxLines = 5)
                    // The last remaining field stays: an entry always has a definition.
                    if (definitions.size > 1) {
                        IconButton(onClick = { definitions.removeAt(index) }) {
                            Icon(Icons.Filled.RemoveCircle,
                                contentDescription = stringResource(R.string.remove_definition),
                                tint = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
            TextButton(onClick = { definitions.add("") }) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.add_definition))
            }

            SectionLabel(stringResource(R.string.notes_optional))
            OutlinedTextField(notes, { notes = it }, label = { Text(stringResource(R.string.notes_hint)) },
                modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 5)

            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }

            if (isEditing) {
                OutlinedButton(onClick = { showDeleteConfirm = true }, enabled = !isSaving,
                    modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.delete_term), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_term)) },
            text = { Text(stringResource(R.string.delete_term_msg)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    val uid = auth.uid
                    val entryId = existing?.id
                    if (uid != null && entryId != null) {
                        isSaving = true
                        scope.launch {
                            try {
                                GlossaryRepository.deleteEntry(uid, glossaryId, entryId)
                                nav.pop()
                            } catch (e: Exception) { error = e.localizedMessage; isSaving = false }
                        }
                    }
                }) { Text(stringResource(R.string.delete)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}
