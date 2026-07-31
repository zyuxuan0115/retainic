package com.retainic.app.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.audio.PronunciationRecorder
import com.retainic.app.data.AuthService
import com.retainic.app.data.PartOfSpeech
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import com.retainic.app.i18n.Language
import kotlinx.coroutines.launch
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddWordScreen(
    auth: AuthService,
    listId: String,
    learning: String,
    original: String,
    ttsEnabled: Boolean,
    existing: VocabWord?,
    nav: ListsNav,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val preferred = LocalAppLanguage.current
    val isEditing = existing != null
    val isLearningJapanese = learning == "ja"
    val isLearningChinese = learning == "zh"

    var term by remember { mutableStateOf(existing?.term ?: "") }
    val translations = remember {
        mutableStateListOf<String>().apply {
            addAll(existing?.translationValues.orEmpty().ifEmpty { listOf("") })
        }
    }
    var notes by remember { mutableStateOf(existing?.notes ?: "") }
    val selectedPOS = remember { mutableStateListOf<PartOfSpeech>().apply { existing?.partOfSpeechValues?.let { addAll(it) } } }
    var hiragana by remember { mutableStateOf(existing?.hiragana ?: "") }
    var pinyin by remember { mutableStateOf(existing?.pinyin ?: "") }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    val recorder = remember { PronunciationRecorder(context) }
    LaunchedEffect(Unit) { recorder.configure(existing?.audioPath) }
    DisposableEffect(Unit) { onDispose { recorder.stopPlayback() } }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) recorder.startRecording() else recorder.permissionDenied = true
    }

    fun toggleRecording() {
        if (recorder.isRecording) {
            recorder.stopRecording()
        } else {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            if (granted) recorder.startRecording() else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    val factValues = translations.map { it.trim() }.filter { it.isNotEmpty() }
    val hasChanges = run {
        if (existing == null) true
        else term.trim() != existing.term ||
            factValues != existing.translationValues ||
            notes.trim() != existing.notes ||
            hiragana.trim() != (existing.hiragana ?: "") ||
            pinyin.trim() != (existing.pinyin ?: "") ||
            selectedPOS.toSet() != existing.partOfSpeechValues.toSet() ||
            recorder.hasNewRecording ||
            (existing.audioPath != null && !recorder.hasAudio)
    }
    val canSave = term.trim().isNotEmpty() && factValues.isNotEmpty() && !isSaving &&
        (!isLearningChinese || pinyin.trim().isNotEmpty()) && hasChanges

    fun save() {
        val uid = auth.uid ?: return
        val newAudio = recorder.recordedFile
        val removeAudio = isEditing && existing?.audioPath != null && !recorder.hasAudio
        val posList = PartOfSpeech.selectable.filter { selectedPOS.contains(it) }
        val facts = factValues
        val legacyTranslation = facts.firstOrNull() ?: return
        isSaving = true
        error = null
        scope.launch {
            try {
                if (existing != null) {
                    val w = existing.copy(
                        term = term.trim(),
                        translation = legacyTranslation,
                        translations = facts,
                        notes = notes.trim(),
                        partsOfSpeech = posList.map { it.raw },
                        partOfSpeech = null,
                        hiragana = hiragana.trim().ifEmpty { null },
                        pinyin = pinyin.trim().ifEmpty { null },
                    )
                    VocabRepository.updateWord(uid, listId, w, newAudioFile = newAudio,
                        removeAudio = removeAudio, ttsEnabled = ttsEnabled)
                } else {
                    val w = VocabWord(
                        term = term.trim(),
                        translation = legacyTranslation,
                        translations = facts,
                        notes = notes.trim(),
                        partsOfSpeech = posList.map { it.raw },
                        hiragana = hiragana.trim().ifEmpty { null },
                        pinyin = pinyin.trim().ifEmpty { null },
                        createdAt = Date(),
                    )
                    VocabRepository.addWord(uid, listId, w, newAudio)
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
                title = { Text(stringResource(if (isEditing) R.string.edit_word else R.string.new_word)) },
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
            SectionLabel(Language.named(learning)?.displayName(preferred) ?: stringResource(R.string.word))
            OutlinedTextField(term, { term = it }, label = { Text(stringResource(R.string.word_youre_learning)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())

            if (isLearningJapanese) {
                SectionLabel(stringResource(R.string.hiragana_optional))
                OutlinedTextField(hiragana, { hiragana = it }, label = { Text(stringResource(R.string.hiragana_hint)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            if (isLearningChinese) {
                SectionLabel(stringResource(R.string.pinyin_required))
                OutlinedTextField(pinyin, { pinyin = it }, label = { Text(stringResource(R.string.pinyin_hint)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                if (pinyin.trim().isEmpty()) {
                    Text(stringResource(R.string.pinyin_required_footer), color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall)
                }
            }

            SectionLabel(Language.named(original)?.displayName(preferred) ?: stringResource(R.string.translation))
            translations.forEachIndexed { index, fact ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        fact,
                        { translations[index] = it },
                        label = { Text(stringResource(R.string.translation)) },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    if (translations.size > 1) {
                        IconButton(onClick = { translations.removeAt(index) }) {
                            Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete),
                                tint = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
            TextButton(onClick = { translations.add("") }) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.add))
            }

            SectionLabel(stringResource(R.string.part_of_speech))
            PartOfSpeech.selectable.forEach { pos ->
                Row(
                    Modifier.fillMaxWidth().clickable {
                        if (selectedPOS.contains(pos)) selectedPOS.remove(pos) else selectedPOS.add(pos)
                    }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(pos.label(preferred), Modifier.weight(1f))
                    if (selectedPOS.contains(pos)) {
                        Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            Text(stringResource(R.string.select_all_apply), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)

            // Pronunciation
            SectionLabel(stringResource(R.string.pronunciation_optional))
            OutlinedButton(onClick = { toggleRecording() }, modifier = Modifier.fillMaxWidth()) {
                Icon(if (recorder.isRecording) Icons.Filled.Stop else Icons.Filled.Mic, contentDescription = null,
                    tint = if (recorder.isRecording) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text(
                    when {
                        recorder.isRecording -> stringResource(R.string.stop_recording)
                        recorder.hasAudio -> stringResource(R.string.re_record)
                        else -> stringResource(R.string.record)
                    }
                )
            }
            if (recorder.hasAudio && !recorder.isRecording) {
                OutlinedButton(
                    onClick = { if (recorder.isPlaying) recorder.stopPlayback() else recorder.play(scope) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(if (recorder.isPlaying) Icons.Filled.Stop else Icons.Filled.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(if (recorder.isPlaying) R.string.stop else R.string.play))
                }
                OutlinedButton(onClick = { recorder.clear() }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.delete_recording), color = MaterialTheme.colorScheme.error)
                }
            }
            if (recorder.permissionDenied) {
                Text(stringResource(R.string.mic_access_off), color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall)
            } else if (recorder.recordingWasEmpty) {
                Text(stringResource(R.string.no_audio_captured), color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall)
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
                    Text(stringResource(R.string.delete_word), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_word)) },
            text = { Text(stringResource(R.string.delete_word_msg)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    val uid = auth.uid
                    val wordId = existing?.id
                    if (uid != null && wordId != null) {
                        isSaving = true
                        scope.launch {
                            try {
                                VocabRepository.deleteWord(uid, listId, wordId)
                                nav.pop()
                            } catch (e: Exception) { error = e.localizedMessage; isSaving = false }
                        }
                    }
                }) { Text(stringResource(R.string.delete)) }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}
