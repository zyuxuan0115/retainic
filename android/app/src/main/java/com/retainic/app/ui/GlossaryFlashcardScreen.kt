package com.retainic.app.ui

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.GlossaryAspect
import com.retainic.app.data.GlossaryPracticeCard
import com.retainic.app.data.GlossaryRepository
import com.retainic.app.data.VocabRepository
import kotlinx.coroutines.launch

/**
 * Flip-card practice for a glossary. Same session flow as [FlashcardScreen] (and
 * the same card), but over terms and definitions: two methods instead of three,
 * and no audio.
 *
 * A term that means several things is one card per meaning when the definition
 * is shown first — each definition has its own schedule — and a single card the
 * other way round, revealing them all.
 */
private data class GlossarySessionItem(
    val card: GlossaryPracticeCard,
    val aspect: GlossaryAspect,
    val definitionIndex: Int = 0,
)

private val GlossaryAspect.labelRes: Int
    get() = when (this) {
        GlossaryAspect.TERM -> R.string.term
        GlossaryAspect.DEFINITION -> R.string.definition
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlossaryFlashcardScreen(
    auth: AuthService,
    cards: List<GlossaryPracticeCard>,
    nav: GlossariesNav,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()

    val session = remember { mutableStateListOf<GlossarySessionItem>() }
    var index by remember { mutableIntStateOf(0) }
    var isFlipped by remember { mutableStateOf(false) }
    val selectedAspects = remember { mutableStateListOf(GlossaryAspect.TERM) }
    var correctCount by remember { mutableIntStateOf(0) }
    var totalCards by remember { mutableIntStateOf(0) }
    var isFinished by remember { mutableStateOf(false) }
    var dueOnly by remember { mutableStateOf(true) }

    // The session items one card contributes to a method: in the daily
    // assignment that method must be due; in free practice every unmemorized
    // term counts. Shown a definition, each definition is a card of its own.
    fun items(card: GlossaryPracticeCard, aspect: GlossaryAspect): List<GlossarySessionItem> {
        val entry = card.entry
        if (aspect == GlossaryAspect.TERM) {
            val include = if (dueOnly) entry.isTermDue() else entry.remember_final != true
            return if (include) listOf(GlossarySessionItem(card, aspect)) else emptyList()
        }
        val indexes = when {
            dueOnly -> entry.dueDefinitionIndexes()
            entry.remember_final != true -> entry.definitionList.indices.toList()
            else -> emptyList()
        }
        return indexes.map { GlossarySessionItem(card, aspect, it) }
    }

    fun deck(): List<GlossarySessionItem> {
        if (selectedAspects.isEmpty()) return emptyList()
        val out = mutableListOf<GlossarySessionItem>()
        for (aspect in selectedAspects) {
            for (card in cards) out.addAll(items(card, aspect))
        }
        return out.shuffled()
    }

    val dueCount = selectedAspects.sumOf { aspect -> cards.flatMap { items(it, aspect) }.size }

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
        // Progress is only recorded for the daily assignment; free practice
        // doesn't affect schedules or stats.
        if (dueOnly) {
            if (correct) {
                item.card.entry.markCorrect(item.aspect, item.definitionIndex)
                // Glossary practice shares the daily tallies with list practice,
                // so the Statistics charts count both.
                auth.uid?.let { uid ->
                    scope.launch { runCatching { VocabRepository.recordRemembered(uid, item.aspect.dailyAspect) } }
                }
            } else {
                item.card.entry.markIncorrect(item.aspect)
            }
            auth.uid?.let { uid ->
                scope.launch {
                    runCatching { GlossaryRepository.updateEntry(uid, item.card.glossaryId, item.card.entry) }
                }
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
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
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
                    description = stringResource(R.string.nothing_to_practice_glossary_desc),
                )
                session.isEmpty() -> GlossarySetupView(
                    dueOnly = dueOnly, onDueOnlyChange = { dueOnly = it },
                    dueCount = dueCount,
                    selectedAspects = selectedAspects,
                    canStart = deck().isNotEmpty(),
                    onStart = { startSession() },
                )
                isFinished -> SummaryView(correctCount, totalCards) { resetToSetup() }
                else -> GlossaryPracticeView(
                    item = session[index],
                    index = index,
                    total = session.size,
                    isFlipped = isFlipped,
                    onFlip = { isFlipped = !isFlipped },
                    onAnswer = { handleAnswer(it) },
                )
            }
        }
    }
}

@Composable
private fun GlossarySetupView(
    dueOnly: Boolean,
    onDueOnlyChange: (Boolean) -> Unit,
    dueCount: Int,
    selectedAspects: MutableList<GlossaryAspect>,
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
            GlossaryAspect.entries.forEach { aspect ->
                Row(
                    Modifier.fillMaxWidth().clickable {
                        if (selectedAspects.contains(aspect)) selectedAspects.remove(aspect)
                        else selectedAspects.add(aspect)
                    }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (selectedAspects.contains(aspect)) Icons.Filled.CheckCircle
                        else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (selectedAspects.contains(aspect)) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(aspect.labelRes))
                }
            }
        }

        Button(onClick = onStart, enabled = canStart, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.start_session))
        }
    }
}

@Composable
private fun GlossaryPracticeView(
    item: GlossarySessionItem,
    index: Int,
    total: Int,
    isFlipped: Boolean,
    onFlip: () -> Unit,
    onAnswer: (Boolean) -> Unit,
) {
    val entry = item.card.entry
    val texts = entry.definitionTexts
    // The front is a bare prompt (the term, or one of its definitions); the
    // answer side always reveals the whole entry — the term with everything it
    // can mean.
    val prompt = when (item.aspect) {
        GlossaryAspect.DEFINITION -> texts.getOrElse(item.definitionIndex) { "" }
        GlossaryAspect.TERM -> entry.term
    }
    val answer = if (texts.size > 1) texts.joinToString("\n") { "• $it" } else texts.firstOrNull().orEmpty()

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
            prompt = prompt,
            frontIsPronunciation = false,
            term = entry.term,
            reading = null,
            posLabels = emptyList(),
            translation = answer,
            notes = entry.notes,
            isFlipped = isFlipped,
            onClick = onFlip,
        )

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
