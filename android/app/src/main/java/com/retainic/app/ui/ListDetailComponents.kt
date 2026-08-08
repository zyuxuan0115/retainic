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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.retainic.app.R
import com.retainic.app.audio.AudioPlaybackStore
import com.retainic.app.data.VocabWord
import com.retainic.app.data.VocabularyList

internal enum class WordFilter(val labelRes: Int) {
    ALL(R.string.show_all),
    REMEMBERED(R.string.show_remembered_only),
    UNREMEMBERED(R.string.show_unremembered_only),
}

@Composable
internal fun WordRow(
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ListSettingsDialog(
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
    // The text-to-speech switch is pending until Save: flipping it changes
    // nothing until the checkmark applies it, and closing the panel discards it.
    var tts by remember { mutableStateOf(ttsEnabled) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var showShareConfirm by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    // Save needs a usable name and something to apply: a new name, a flipped
    // text-to-speech switch, or both.
    val canSave = name.trim().isNotEmpty() &&
        (name.trim() != initialName.trim() || tts != ttsEnabled)

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
                        IconButton(
                            onClick = {
                                if (tts != ttsEnabled) onSetTTS(tts)
                                if (name.trim() != initialName.trim()) onSave(name)
                                onDismiss()
                            },
                            enabled = canSave,
                        ) {
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
                    Switch(checked = tts, onCheckedChange = { tts = it })
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
internal fun MoveDestinationDialog(
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
