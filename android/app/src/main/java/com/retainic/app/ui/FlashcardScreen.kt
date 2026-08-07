package com.retainic.app.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.retainic.app.LocalAppLanguage
import com.retainic.app.R
import com.retainic.app.audio.AudioPlaybackStore
import com.retainic.app.data.AuthService
import com.retainic.app.data.PracticeCard
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import kotlinx.coroutines.launch

private enum class FrontMode(val labelRes: Int, val memoryAspect: String) {
    TERM(R.string.word, "spelling"),
    TRANSLATION(R.string.translation, "translation"),
    PRONUNCIATION(R.string.audio, "pronunciation"),
}

private data class SessionItem(val card: PracticeCard, val mode: FrontMode)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlashcardScreen(
    auth: AuthService,
    cards: List<PracticeCard>,
    learning: String,
    ttsEnabled: Boolean,
    nav: ListsNav,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val preferred = LocalAppLanguage.current

    val session = remember { mutableStateListOf<SessionItem>() }
    var index by remember { mutableIntStateOf(0) }
    var isFlipped by remember { mutableStateOf(false) }
    val selectedModes = remember { mutableStateListOf(FrontMode.TERM) }
    var correctCount by remember { mutableIntStateOf(0) }
    var totalCards by remember { mutableIntStateOf(0) }
    var isFinished by remember { mutableStateOf(false) }
    var dueOnly by remember { mutableStateOf(true) }

    fun includes(card: PracticeCard, mode: FrontMode): Boolean {
        if (mode == FrontMode.PRONUNCIATION && card.word.audioPath == null && !ttsEnabled) return false
        return if (dueOnly) {
            when (mode) {
                FrontMode.TRANSLATION -> card.word.isTranslationDue()
                FrontMode.TERM -> card.word.isWordDue()
                FrontMode.PRONUNCIATION -> card.word.isPronunciationDue()
            }
        } else {
            card.word.remember_final != true
        }
    }

    fun deck(): List<SessionItem> {
        if (selectedModes.isEmpty()) return emptyList()
        val items = mutableListOf<SessionItem>()
        for (mode in selectedModes) {
            for (card in cards) if (includes(card, mode)) items.add(SessionItem(card, mode))
        }
        return items.shuffled()
    }

    val dueCount = selectedModes.sumOf { mode -> cards.count { includes(it, mode) } }

    fun startSession() {
        val d = deck()
        if (d.isEmpty()) return
        session.clear(); session.addAll(d)
        totalCards = d.size
        index = 0; correctCount = 0; isFlipped = false; isFinished = false
    }

    fun advance() {
        isFlipped = false
        if (index + 1 < session.size) index += 1 else isFinished = true
    }

    fun handleAnswer(correct: Boolean) {
        val item = session[index]
        if (dueOnly) {
            if (correct) {
                item.card.word.markCorrect(item.mode.memoryAspect, ttsEnabled)
                auth.uid?.let { uid -> scope.launch { runCatching { VocabRepository.recordRemembered(uid, item.mode.memoryAspect) } } }
            } else {
                item.card.word.markIncorrect(item.mode.memoryAspect)
            }
            auth.uid?.let { uid ->
                scope.launch { runCatching { VocabRepository.updateWord(uid, item.card.listId, item.card.word, ttsEnabled = ttsEnabled) } }
            }
        }
        if (correct) correctCount += 1 else session.add(item)
        advance()
    }

    fun resetToSetup() {
        session.clear(); index = 0; correctCount = 0; isFlipped = false; isFinished = false
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.practice)) },
                navigationIcon = {
                    IconButton_Back { nav.pop() }
                },
                actions = {
                    if (session.isNotEmpty() && !isFinished) {
                        TextButton(onClick = { isFinished = true }) { Text(stringResource(R.string.end)) }
                    }
                },
            )
        },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                cards.isEmpty() -> EmptyState(
                    icon = Icons.Outlined.Style,
                    title = stringResource(R.string.nothing_to_practice),
                    description = stringResource(R.string.nothing_to_practice_desc),
                )
                session.isEmpty() -> SetupView(
                    dueOnly = dueOnly, onDueOnlyChange = { dueOnly = it },
                    dueCount = dueCount,
                    selectedModes = selectedModes,
                    ttsEnabled = ttsEnabled,
                    canStart = deck().isNotEmpty(),
                    onStart = { startSession() },
                )
                isFinished -> SummaryView(correctCount, totalCards) { resetToSetup() }
                else -> PracticeView(
                    item = session[index],
                    index = index,
                    total = session.size,
                    isFlipped = isFlipped,
                    onFlip = { isFlipped = !isFlipped },
                    learning = learning,
                    ttsEnabled = ttsEnabled,
                    preferred = preferred,
                    onAnswer = { handleAnswer(it) },
                )
            }
        }
    }
}

@Composable
private fun IconButton_Back(onClick: () -> Unit) {
    androidx.compose.material3.IconButton(onClick = onClick) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
    }
}

@Composable
private fun SetupView(
    dueOnly: Boolean,
    onDueOnlyChange: (Boolean) -> Unit,
    dueCount: Int,
    selectedModes: MutableList<FrontMode>,
    ttsEnabled: Boolean,
    canStart: Boolean,
    onStart: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
    ) {
        Icon(Icons.Outlined.Style, contentDescription = null,
            modifier = Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(R.string.ready_to_practice), style = MaterialTheme.typography.titleLarge)
        Text(
            if (dueCount > 0) stringResource(R.string.n_cards_due, dueCount)
            else stringResource(R.string.finished_daily),
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
        )

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.daily_assignment), Modifier.weight(1f))
            Switch(checked = dueOnly, onCheckedChange = onDueOnlyChange)
        }

        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.show_first), style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            FrontMode.entries.forEach { mode ->
                Row(
                    Modifier.fillMaxWidth().clickable {
                        if (selectedModes.contains(mode)) selectedModes.remove(mode) else selectedModes.add(mode)
                    }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (selectedModes.contains(mode)) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (selectedModes.contains(mode)) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(mode.labelRes))
                }
            }
            if (selectedModes.contains(FrontMode.PRONUNCIATION) && !ttsEnabled) {
                Text(stringResource(R.string.audio_only_recorded), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        Button(onClick = onStart, enabled = canStart, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.start_session))
        }
    }
}

@Composable
private fun PracticeView(
    item: SessionItem,
    index: Int,
    total: Int,
    isFlipped: Boolean,
    onFlip: () -> Unit,
    learning: String,
    ttsEnabled: Boolean,
    preferred: String,
    onAnswer: (Boolean) -> Unit,
) {
    val word = item.card.word
    val mode = item.mode
    val reading = readingFor(word, learning)
    val posLabels = word.partOfSpeechValues.map { it.label(preferred) }
    val pronunciationKey = word.audioPath ?: if (ttsEnabled) AudioPlaybackStore.ttsKey(word.term) else null
    val showAudioButton = if (mode == FrontMode.PRONUNCIATION) !isFlipped else isFlipped

    Column(
        Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        LinearProgressIndicator(
            progress = { if (total == 0) 0f else index.toFloat() / total },
            modifier = Modifier.fillMaxWidth(),
        )
        Text(stringResource(R.string.n_of_m, index + 1, total), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)

        Spacer(Modifier.weight(1f))

        FlipCard(
            prompt = if (mode == FrontMode.TRANSLATION) word.translation else word.term,
            frontIsPronunciation = mode == FrontMode.PRONUNCIATION,
            term = word.term,
            reading = reading,
            posLabels = posLabels,
            translation = word.translation,
            notes = word.notes,
            isFlipped = isFlipped,
            onClick = onFlip,
        )

        if (showAudioButton && pronunciationKey != null) {
            OutlinedButton(onClick = {
                word.audioPath?.let { AudioPlaybackStore.toggle(it) }
                    ?: AudioPlaybackStore.toggleSpeak(word.term, learning)
            }) {
                Icon(if (AudioPlaybackStore.playingPath == pronunciationKey) Icons.Filled.Stop else Icons.Filled.VolumeUp,
                    contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(if (AudioPlaybackStore.playingPath == pronunciationKey) R.string.stop else R.string.play_pronunciation))
            }
        }

        Spacer(Modifier.weight(1f))

        if (isFlipped) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = { onAnswer(false) },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF59E0B)),
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Filled.Autorenew, contentDescription = null)
                    Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.practice_again))
                }
                Button(
                    onClick = { onAnswer(true) },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF22C55E)),
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Filled.Check, contentDescription = null)
                    Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.got_it))
                }
            }
        } else {
            Text(stringResource(R.string.tap_reveal), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.height(44.dp))
        }
    }
}

/** The flip card itself. Shared with glossary practice, which fills the answer
 *  side with a term and its definition and leaves the word-only fields empty. */
@Composable
internal fun FlipCard(
    prompt: String,
    frontIsPronunciation: Boolean,
    term: String,
    reading: String?,
    posLabels: List<String>,
    translation: String,
    notes: String,
    isFlipped: Boolean,
    onClick: () -> Unit,
) {
    val bg by animateColorAsState(
        if (isFlipped) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        else MaterialTheme.colorScheme.surfaceVariant,
        label = "cardBg",
    )
    Box(
        Modifier.fillMaxWidth().height(280.dp)
            .background(bg, RoundedCornerShape(24.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (isFlipped) stringResource(R.string.answer) else stringResource(R.string.tap_to_flip),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.TopCenter).padding(8.dp),
        )
        if (isFlipped) {
            Column(
                Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(term, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                reading?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (posLabels.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        posLabels.forEach { PosChip(it) }
                    }
                }
                HorizontalDivider(Modifier.padding(horizontal = 32.dp))
                Text(translation, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                if (notes.isNotEmpty()) {
                    Text(notes, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                }
            }
        } else if (frontIsPronunciation) {
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.VolumeUp, contentDescription = null, modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.listen_and_recall), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Text(prompt, fontSize = 32.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                modifier = Modifier.padding(32.dp))
        }
    }
}

/** End-of-session results, shared with glossary practice. */
@Composable
internal fun SummaryView(correctCount: Int, totalCards: Int, onDone: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        Icon(Icons.Filled.CheckCircle, contentDescription = null, modifier = Modifier.size(64.dp),
            tint = Color(0xFF22C55E))
        Text(stringResource(R.string.session_complete), style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.got_n_of_m_right, correctCount, totalCards),
            style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.done)) }
    }
}

private fun readingFor(word: VocabWord, learning: String): String? {
    val value = when (learning) {
        "zh" -> word.pinyin
        "ja" -> word.hiragana
        else -> word.reading
    }
    return value?.takeIf { it.isNotEmpty() }
}
