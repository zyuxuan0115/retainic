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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.SharedList
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import com.retainic.app.data.VocabularyList
import com.retainic.app.i18n.Language
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VocabListsScreen(auth: AuthService, nav: ListsNav, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var lists by remember { mutableStateOf<List<VocabularyList>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showNewList by remember { mutableStateOf(false) }
    var pendingTrash by remember { mutableStateOf<List<VocabularyList>>(emptyList()) }

    suspend fun load() {
        val uid = auth.uid ?: return
        isLoading = true
        try {
            lists = VocabRepository.fetchLists(uid)
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
            // Both actions sit at the trailing edge, leaving the title the
            // whole leading side. The plus stays rightmost.
            TopAppBar(
                title = { Text(stringResource(R.string.lists)) },
                actions = {
                    IconButton(onClick = { nav.push(ListsRoute.Trash) }) {
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.trash))
                    }
                    IconButton(onClick = { showNewList = true }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.new_list))
                    }
                },
            )
        },
    ) { inner ->
        // The banner sits above the list rather than over it, so the saved
        // copy below is never partly hidden by the notice explaining it.
        Column(Modifier.padding(inner).fillMaxSize()) {
            OfflineBanner()
            Box(Modifier.fillMaxSize()) {
                when {
                    isLoading && lists.isEmpty() -> LoadingView(stringResource(R.string.loading))
                    lists.isEmpty() -> EmptyState(
                        icon = Icons.Filled.Layers,
                        title = stringResource(R.string.no_lists_yet),
                        description = stringResource(R.string.create_first_list),
                        actionLabel = stringResource(R.string.create_a_list),
                        onAction = { showNewList = true },
                    )
                    else -> LazyColumn(Modifier.fillMaxSize()) {
                        items(lists, key = { it.id ?: it.name }) { list ->
                            val dismissState = rememberSwipeToDismissBoxState(
                                confirmValueChange = { value ->
                                    if (value == SwipeToDismissBoxValue.EndToStart) {
                                        pendingTrash = listOf(list)
                                    }
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
                                // The row needs a surface of its own: without one it
                                // is transparent, and the red swipe-to-delete layer
                                // behind it shows through every list at rest.
                                ListRow(
                                    list,
                                    Modifier
                                        .background(MaterialTheme.colorScheme.surface)
                                        .clickable { nav.push(ListsRoute.Detail(list)) },
                                )
                            }
                            RowDivider()
                        }
                    }
                }
            }
        }
    }

    if (showNewList) {
        NewListDialog(
            uid = auth.uid,
            onDismiss = { showNewList = false },
            onCreated = { showNewList = false; scope.launch { load() } },
        )
    }

    if (pendingTrash.isNotEmpty()) {
        val target = pendingTrash
        AlertDialog(
            onDismissRequest = { pendingTrash = emptyList() },
            title = { Text(stringResource(R.string.move_to_trash)) },
            text = {
                Text(
                    if (target.size == 1) stringResource(R.string.list_will_move_trash, target[0].name)
                    else stringResource(R.string.selected_lists_move_trash)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val uid = auth.uid
                    pendingTrash = emptyList()
                    if (uid != null) scope.launch {
                        for (l in target) {
                            val id = l.id ?: continue
                            try {
                                VocabRepository.trashList(uid, id)
                                lists = lists.filterNot { it.id == id }
                            } catch (e: Exception) { error = e.localizedMessage }
                        }
                    }
                }) { Text(stringResource(R.string.move_to_trash)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingTrash = emptyList() }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    ErrorDialog(error) { error = null }
}

@Composable
fun ListRow(list: VocabularyList, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Filled.Layers, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Column {
            Text(list.name, style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.n_words, list.wordCount),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// MARK: - New list / import dialog

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewListDialog(uid: String?, onDismiss: () -> Unit, onCreated: () -> Unit) {
    val preferred = LocalAppLanguage.current
    val scope = rememberCoroutineScope()

    var importMode by remember { mutableStateOf(false) }
    // Create
    var name by remember { mutableStateOf("") }
    var learning by remember { mutableStateOf("") }
    var original by remember { mutableStateOf(preferred) }
    // Import step 1
    var importId by remember { mutableStateOf("") }
    var isLookingUp by remember { mutableStateOf(false) }
    var lookupError by remember { mutableStateOf<String?>(null) }
    // Import step 2
    var pendingImport by remember { mutableStateOf<SharedList?>(null) }
    var importName by remember { mutableStateOf("") }
    var isImporting by remember { mutableStateOf(false) }

    val canCreate = name.trim().isNotEmpty() && learning.isNotEmpty() &&
        original.isNotEmpty() && learning != original

    fun lookUp() {
        val id = importId.trim()
        if (id.isEmpty() || uid == null) return
        isLookingUp = true
        lookupError = null
        scope.launch {
            try {
                val shared = VocabRepository.fetchSharedList(id)
                if (shared != null) {
                    importName = shared.list.name
                    pendingImport = shared
                } else {
                    lookupError = null // set via resource below
                    lookupError = "no"
                }
            } catch (e: Exception) {
                lookupError = e.localizedMessage
            }
            isLookingUp = false
        }
    }

    fun performImport(shared: SharedList) {
        if (uid == null) return
        isImporting = true
        scope.launch {
            try {
                val finalName = importName.trim().ifEmpty { shared.list.name }
                val newListId = VocabRepository.createList(
                    uid, finalName,
                    shared.list.learningLanguage ?: "",
                    shared.list.originalLanguage ?: "",
                )
                val words = shared.words.map { source ->
                    VocabWord(
                        term = source.term,
                        translation = source.translation,
                        notes = source.notes,
                        partsOfSpeech = source.partOfSpeechValues.map { it.raw },
                        hiragana = source.hiragana,
                        pinyin = source.pinyin,
                        createdAt = java.util.Date(),
                    )
                }
                VocabRepository.addWords(uid, newListId, words)
                isImporting = false
                onCreated()
            } catch (e: Exception) {
                lookupError = e.localizedMessage
                isImporting = false
            }
        }
    }

    Dialog(onDismissRequest = { if (!isImporting) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.new_list)) },
                    navigationIcon = {
                        IconButton(onClick = { if (pendingImport != null) pendingImport = null else onDismiss() },
                            enabled = !isImporting) {
                            Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel))
                        }
                    },
                    actions = {
                        when {
                            isLookingUp || isImporting -> CircularProgressIndicator(Modifier.size(22.dp).padding(end = 8.dp), strokeWidth = 2.dp)
                            pendingImport != null -> IconButton(
                                onClick = { pendingImport?.let { performImport(it) } },
                                enabled = importName.trim().isNotEmpty(),
                            ) { Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.add)) }
                            !importMode -> IconButton(
                                onClick = {
                                    if (uid != null) scope.launch {
                                        try {
                                            VocabRepository.createList(uid, name.trim(), learning, original)
                                            onCreated()
                                        } catch (e: Exception) { lookupError = e.localizedMessage }
                                    }
                                },
                                enabled = canCreate,
                            ) { Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.create)) }
                            else -> IconButton(onClick = { lookUp() }, enabled = importId.trim().isNotEmpty()) {
                                Icon(Icons.AutoMirrored.Filled.Login, contentDescription = stringResource(R.string.import_action))
                            }
                        }
                    },
                )
            },
        ) { inner ->
            Column(
                Modifier.padding(inner).fillMaxSize().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                val shared = pendingImport
                if (shared != null) {
                    Text(stringResource(R.string.import_successful), style = MaterialTheme.typography.titleLarge)
                    Text(stringResource(R.string.found_wordlist_n, shared.words.size),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedTextField(importName, { importName = it },
                        label = { Text(stringResource(R.string.list_name)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    lookupError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                } else {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        SegmentedButton(selected = !importMode, onClick = { importMode = false },
                            shape = SegmentedButtonDefaults.itemShape(0, 2)) {
                            Text(stringResource(R.string.create_new))
                        }
                        SegmentedButton(selected = importMode, onClick = { importMode = true },
                            shape = SegmentedButtonDefaults.itemShape(1, 2)) {
                            Text(stringResource(R.string.import_by_id))
                        }
                    }
                    if (!importMode) {
                        OutlinedTextField(name, { name = it },
                            label = { Text(stringResource(R.string.list_name)) },
                            placeholder = { Text(stringResource(R.string.eg_kitchen)) },
                            singleLine = true, modifier = Modifier.fillMaxWidth())
                        LanguageDropdown(stringResource(R.string.im_learning), learning, preferred) { learning = it }
                        LanguageDropdown(stringResource(R.string.translated_into), original, preferred) { original = it }
                        if (learning.isNotEmpty() && learning == original) {
                            Text(stringResource(R.string.two_languages_different), color = MaterialTheme.colorScheme.error)
                        }
                    } else {
                        OutlinedTextField(importId, { importId = it },
                            label = { Text(stringResource(R.string.unique_id)) },
                            placeholder = { Text(stringResource(R.string.paste_unique_id)) },
                            singleLine = true, modifier = Modifier.fillMaxWidth())
                        Text(
                            if (lookupError == "no") stringResource(R.string.no_wordlist_found)
                            else lookupError ?: stringResource(R.string.import_id_footer),
                            color = if (lookupError != null) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LanguageDropdown(label: String, selected: String, preferred: String, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val display = Language.named(selected)?.displayName(preferred) ?: stringResource(R.string.select_ellipsis)
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = display,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Language.all.forEach { lang ->
                DropdownMenuItem(
                    text = { Text(lang.displayName(preferred)) },
                    onClick = { onSelect(lang.code); expanded = false },
                )
            }
        }
    }
}
