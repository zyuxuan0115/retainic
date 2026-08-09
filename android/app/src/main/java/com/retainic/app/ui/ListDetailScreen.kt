package com.retainic.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.PlaylistAddCheck
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.PracticeCard
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import com.retainic.app.data.VocabularyList
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListDetailScreen(
    auth: AuthService,
    list: VocabularyList,
    nav: ListsNav,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val preferred = LocalAppLanguage.current
    val listId = list.id ?: ""
    val learning = list.learningLanguage ?: ""
    val original = list.originalLanguage ?: ""

    val words = remember { mutableStateListOf<VocabWord>() }
    var isLoading by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var listName by remember { mutableStateOf(list.name) }
    var ttsEnabled by remember { mutableStateOf(list.ttsEnabled ?: false) }
    var searchText by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(WordFilter.ALL) }

    var selecting by remember { mutableStateOf(false) }
    val selection = remember { mutableStateListOf<String>() }

    var showSettings by remember { mutableStateOf(false) }
    var showMove by remember { mutableStateOf(false) }
    var moveTargets by remember { mutableStateOf<List<VocabularyList>>(emptyList()) }

    var pendingDelete by remember { mutableStateOf<List<VocabWord>>(emptyList()) }
    var pendingDeleteIsSelection by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    suspend fun load() {
        val uid = auth.uid ?: return
        isLoading = true
        try {
            words.clear()
            words.addAll(VocabRepository.fetchWords(uid, listId))
        } catch (e: Exception) {
            error = e.localizedMessage
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(auth.uid, listId) { load() }

    val filtered = words.filter { w ->
        (when (filter) {
            WordFilter.ALL -> true
            WordFilter.REMEMBERED -> w.isRemembered
            WordFilter.UNREMEMBERED -> !w.isRemembered
        }) && (searchText.isEmpty() ||
            w.term.contains(searchText, ignoreCase = true) ||
            w.translation.contains(searchText, ignoreCase = true))
    }

    fun endSelection() { selecting = false; selection.clear() }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (selecting) {
                            if (selection.isEmpty()) stringResource(R.string.select_words)
                            else stringResource(R.string.n_selected, selection.size)
                        } else listName
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
                    if (!selecting && words.isNotEmpty()) {
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
                    Spacer(Modifier.width(8.dp))
                    TextButton(
                        onClick = {
                            scope.launch {
                                val uid = auth.uid ?: return@launch
                                moveTargets = VocabRepository.fetchLists(uid).filter {
                                    it.id != listId && it.learningLanguage == list.learningLanguage &&
                                        it.originalLanguage == list.originalLanguage
                                }
                                showMove = true
                            }
                        },
                        enabled = selection.isNotEmpty() && !isBusy,
                    ) {
                        Icon(Icons.Filled.Folder, contentDescription = null)
                        Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.move))
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = {
                            pendingDelete = words.filter { selection.contains(it.id ?: "") }
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
                    if (words.isNotEmpty()) {
                        TextButton(onClick = {
                            val cards = words.map { PracticeCard(it, listId) }
                            nav.push(ListsRoute.Practice(cards, learning, ttsEnabled))
                        }) {
                            Icon(Icons.Outlined.Style, contentDescription = null)
                            Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.practice))
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.list_settings))
                    }
                    IconButton(onClick = {
                        nav.push(ListsRoute.Editor(listId, learning, original, ttsEnabled, null))
                    }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_word))
                    }
                }
            }
        },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                isLoading && words.isEmpty() -> LoadingView(stringResource(R.string.loading))
                words.isEmpty() -> EmptyState(
                    icon = Icons.Outlined.Style,
                    title = stringResource(R.string.no_words_yet),
                    description = stringResource(R.string.add_words_to_list, listName),
                    actionLabel = stringResource(R.string.add_first_word),
                    onAction = { nav.push(ListsRoute.Editor(listId, learning, original, ttsEnabled, null)) },
                )
                else -> Column(Modifier.fillMaxSize()) {
                    OutlinedTextField(
                        searchText, { searchText = it },
                        placeholder = { Text(stringResource(R.string.search_words)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(filtered, key = { it.idValue }) { word ->
                            WordRow(
                                word = word,
                                learning = learning,
                                ttsEnabled = ttsEnabled,
                                preferred = preferred,
                                selecting = selecting,
                                selected = selection.contains(word.id ?: ""),
                                onClick = {
                                    if (selecting) {
                                        val id = word.id ?: return@WordRow
                                        if (selection.contains(id)) selection.remove(id) else selection.add(id)
                                    } else {
                                        nav.push(ListsRoute.Editor(listId, learning, original, ttsEnabled, word))
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
                    if (pendingDelete.size == 1) stringResource(R.string.delete_this_word)
                    else stringResource(R.string.delete_n_words, pendingDelete.size)
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
                        for (w in toDelete) {
                            val id = w.id ?: continue
                            try {
                                VocabRepository.deleteWord(uid, listId, id)
                                words.removeAll { it.id == id }
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
        ListSettingsDialog(
            initialName = listName,
            filter = filter,
            onFilterChange = { filter = it },
            ttsEnabled = ttsEnabled,
            publicId = list.publicId,
            onDismiss = { showSettings = false },
            onSave = { newName ->
                val trimmed = newName.trim()
                if (trimmed.isNotEmpty()) {
                    listName = trimmed
                    val uid = auth.uid
                    if (uid != null) scope.launch {
                        try { VocabRepository.renameList(uid, listId, trimmed) }
                        catch (e: Exception) { error = e.localizedMessage }
                    }
                }
                showSettings = false
            },
            onSetTTS = { enabled ->
                ttsEnabled = enabled
                val uid = auth.uid
                if (uid != null) scope.launch {
                    isBusy = true
                    try {
                        VocabRepository.setListTTS(uid, listId, enabled)
                        for (i in words.indices) {
                            val w = words[i]
                            w.refreshMemorization(enabled)
                            VocabRepository.updateWord(uid, listId, w, ttsEnabled = enabled)
                        }
                    } catch (e: Exception) { error = e.localizedMessage }
                    isBusy = false
                }
            },
            onResetMemory = {
                showSettings = false
                val uid = auth.uid
                if (uid != null) scope.launch {
                    isBusy = true
                    try {
                        for (i in words.indices) {
                            val w = words[i]
                            w.resetMemory()
                            VocabRepository.updateWord(uid, listId, w)
                        }
                    } catch (e: Exception) { error = e.localizedMessage }
                    isBusy = false
                }
            },
        )
    }

    if (showMove) {
        MoveDestinationDialog(
            targets = moveTargets,
            count = selection.size,
            onDismiss = { showMove = false },
            onSelect = { destination ->
                showMove = false
                val uid = auth.uid
                val destId = destination.id
                if (uid != null && destId != null) {
                    val ids = selection.toList()
                    scope.launch {
                        isBusy = true
                        try {
                            for (w in words.filter { ids.contains(it.id ?: "") }) {
                                VocabRepository.moveWord(uid, listId, destId, w)
                            }
                            words.removeAll { ids.contains(it.id ?: "") }
                        } catch (e: Exception) { error = e.localizedMessage }
                        isBusy = false
                        endSelection()
                    }
                }
            },
        )
    }

    ErrorDialog(error) { error = null }
}
