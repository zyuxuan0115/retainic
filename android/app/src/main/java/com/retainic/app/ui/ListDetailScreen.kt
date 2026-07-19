package com.retainic.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.PlaylistAddCheck
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.VolumeUp
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
import androidx.compose.material3.Switch
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
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.audio.AudioPlaybackStore
import com.retainic.app.data.AuthService
import com.retainic.app.data.PracticeCard
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import com.retainic.app.data.VocabularyList
import kotlinx.coroutines.launch

private enum class WordFilter(val labelRes: Int) {
    ALL(R.string.show_all),
    REMEMBERED(R.string.show_remembered_only),
    UNREMEMBERED(R.string.show_unremembered_only),
}

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
                            HorizontalDivider()
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

@Composable
private fun WordRow(
    word: VocabWord,
    learning: String,
    ttsEnabled: Boolean,
    preferred: String,
    selecting: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val pronunciationKey = word.audioPath ?: if (ttsEnabled) AudioPlaybackStore.ttsKey(word.term) else null

    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selecting) {
            Checkbox(checked = selected, onCheckedChange = { onClick() })
            Spacer(Modifier.width(8.dp))
        }
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(word.term, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                word.reading?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                word.partOfSpeechValues.forEach { pos ->
                    PosChip(pos.label(preferred))
                }
            }
            Text(word.translation, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (pronunciationKey != null && !selecting) {
            IconButton(onClick = {
                word.audioPath?.let { AudioPlaybackStore.toggle(it) }
                    ?: AudioPlaybackStore.toggleSpeak(word.term, learning)
            }) {
                Icon(
                    if (AudioPlaybackStore.playingPath == pronunciationKey) Icons.Filled.Stop else Icons.Filled.VolumeUp,
                    contentDescription = stringResource(R.string.play_pronunciation),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
fun PosChip(label: String) {
    Text(
        label,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ListSettingsDialog(
    initialName: String,
    filter: WordFilter,
    onFilterChange: (WordFilter) -> Unit,
    ttsEnabled: Boolean,
    publicId: String?,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
    onSetTTS: (Boolean) -> Unit,
    onResetMemory: () -> Unit,
) {
    var name by remember { mutableStateOf(initialName) }
    var tts by remember { mutableStateOf(ttsEnabled) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var showShareConfirm by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    val canSave = name.trim().isNotEmpty() && name.trim() != initialName.trim()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.list_settings)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.cancel))
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
                OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.list_name)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())

                Text(stringResource(R.string.show_words), style = MaterialTheme.typography.titleSmall)
                WordFilter.entries.forEach { option ->
                    Row(Modifier.fillMaxWidth().clickable { onFilterChange(option) },
                        verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = filter == option, onClick = { onFilterChange(option) })
                        Text(stringResource(option.labelRes))
                    }
                }

                HorizontalDivider()
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.text_to_speech))
                        Text(stringResource(R.string.tts_footer), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = tts, onCheckedChange = { tts = it; onSetTTS(it) })
                }

                HorizontalDivider()
                TextButton(
                    onClick = {
                        val id = publicId
                        if (!id.isNullOrEmpty()) { clipboard.setText(AnnotatedString(id)); showShareConfirm = true }
                    },
                    enabled = !publicId.isNullOrEmpty(),
                ) { Text(stringResource(R.string.share_list)) }
                Text(stringResource(R.string.share_list_footer), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)

                HorizontalDivider()
                TextButton(onClick = { showResetConfirm = true }) {
                    Text(stringResource(R.string.mark_all_not_remembered), color = MaterialTheme.colorScheme.error)
                }
                Text(stringResource(R.string.mark_all_not_remembered_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text(stringResource(R.string.mark_all_not_remembered_title)) },
            confirmButton = {
                TextButton(onClick = { showResetConfirm = false; onResetMemory() }) {
                    Text(stringResource(R.string.mark_all_not_remembered_action))
                }
            },
            dismissButton = { TextButton(onClick = { showResetConfirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    if (showShareConfirm) {
        AlertDialog(
            onDismissRequest = { showShareConfirm = false },
            title = { Text(stringResource(R.string.unique_id_copied)) },
            text = { Text(stringResource(R.string.unique_id_copied_msg)) },
            confirmButton = { TextButton(onClick = { showShareConfirm = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MoveDestinationDialog(
    targets: List<VocabularyList>,
    count: Int,
    onDismiss: () -> Unit,
    onSelect: (VocabularyList) -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.move_n_words, count)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.cancel))
                        }
                    },
                )
            },
        ) { inner ->
            Box(Modifier.padding(inner).fillMaxSize()) {
                if (targets.isEmpty()) {
                    EmptyState(
                        icon = Icons.Filled.Folder,
                        title = stringResource(R.string.no_compatible_lists),
                        description = stringResource(R.string.no_compatible_lists_desc),
                    )
                } else {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(targets, key = { it.id ?: it.name }) { list ->
                            ListRow(list, Modifier.clickable { onSelect(list) })
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}
