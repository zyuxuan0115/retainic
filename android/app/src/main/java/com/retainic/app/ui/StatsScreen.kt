package com.retainic.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Icon
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.foundation.Canvas
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.GlossaryEntry
import com.retainic.app.data.GlossaryRepository
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private val AspectColors = listOf(Color(0xFF3B82F6), Color(0xFF22C55E), Color(0xFFF59E0B))

/**
 * Glossary practice records the same daily tallies as list practice, so the
 * totals cover both a user's words and their glossary terms.
 */
private class LearningStats(words: List<VocabWord>, entries: List<GlossaryEntry> = emptyList()) {
    val totalWords = words.size + entries.size
    val totalMemorized = words.count { it.isRemembered } + entries.count { it.isRemembered }
    val startDate: Date? = (words.mapNotNull { it.createdAt } + entries.mapNotNull { it.createdAt })
        .minByOrNull { it.time }
    val activeDays: Int
    val perDay: Double
    val perWeek: Double
    val perMonth: Double

    init {
        val now = Date()
        activeDays = if (startDate != null) {
            maxOf(1, VocabWord.daysBetween(VocabWord.startOfDay(startDate), VocabWord.startOfDay(now)) + 1)
        } else 1
        perDay = totalMemorized.toDouble() / activeDays
        perWeek = perDay * 7
        perMonth = perDay * (365.25 / 12)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(auth: AuthService, modifier: Modifier = Modifier) {
    var stats by remember { mutableStateOf<LearningStats?>(null) }
    var today by remember { mutableStateOf(mapOf("word" to 0, "translation" to 0, "pronunciation" to 0)) }
    var week by remember { mutableStateOf<List<Triple<Date, String, Int>>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(auth.uid) {
        val uid = auth.uid ?: return@LaunchedEffect
        isLoading = true
        try {
            val lists = VocabRepository.fetchLists(uid)
            val all = mutableListOf<VocabWord>()
            for (list in lists) {
                val id = list.id ?: continue
                all += VocabRepository.fetchWords(uid, id)
            }
            val glossaries = GlossaryRepository.fetchGlossaries(uid)
            val allEntries = mutableListOf<GlossaryEntry>()
            for (glossary in glossaries) {
                val id = glossary.id ?: continue
                allEntries += GlossaryRepository.fetchEntries(uid, id)
            }
            stats = LearningStats(all, allEntries)
            today = countTodayRemembered(all, allEntries)
            val daily = runCatching { VocabRepository.fetchDailyStats(uid, 7) }.getOrDefault(emptyList())
            week = buildWeekPoints(daily, today)
        } catch (e: Exception) {
            error = e.localizedMessage
        } finally {
            isLoading = false
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.statistics)) }) },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            val s = stats
            when {
                isLoading && s == null -> LoadingView(stringResource(R.string.loading))
                s == null || s.totalWords == 0 -> EmptyState(
                    icon = Icons.Filled.BarChart,
                    title = stringResource(R.string.no_stats_yet),
                    description = stringResource(R.string.no_stats_desc),
                )
                else -> StatsContent(s, today, week)
            }
        }
    }

    ErrorDialog(error) { error = null }
}

@Composable
private fun StatsContent(
    stats: LearningStats,
    today: Map<String, Int>,
    week: List<Triple<Date, String, Int>>,
) {
    val aspectKeys = listOf("word", "translation", "pronunciation")
    val aspectLabels = listOf(stringResource(R.string.word), stringResource(R.string.translation), stringResource(R.string.pronunciation))

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        // Total memorized card
        Column(
            Modifier.fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(20.dp))
                .padding(vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Filled.Psychology, contentDescription = null, modifier = Modifier.size(44.dp),
                tint = MaterialTheme.colorScheme.primary)
            Text("${stats.totalMemorized}", fontSize = 52.sp, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.words_and_terms_memorized), style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(stringResource(R.string.out_of_n_total, stats.totalWords),
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        // Remembered today (bar chart)
        Text(stringResource(R.string.remembered_today), style = MaterialTheme.typography.titleMedium)
        BarChart(aspectKeys.mapIndexed { i, k -> Triple(aspectLabels[i], today[k] ?: 0, AspectColors[i]) })

        // This week (line chart)
        Text(stringResource(R.string.this_week), style = MaterialTheme.typography.titleMedium)
        WeekLineChart(week, aspectKeys, aspectLabels, AspectColors)

        // Average pace
        Text(stringResource(R.string.average_pace), style = MaterialTheme.typography.titleMedium)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PaceCard(stringResource(R.string.per_day), stats.perDay, Modifier.weight(1f))
            PaceCard(stringResource(R.string.per_week), stats.perWeek, Modifier.weight(1f))
            PaceCard(stringResource(R.string.per_month), stats.perMonth, Modifier.weight(1f))
        }

        stats.startDate?.let { start ->
            val since = DateFormat.getDateInstance(DateFormat.MEDIUM, Locale.getDefault()).format(start)
            Text(stringResource(R.string.based_on_days, stats.activeDays, since),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun PaceCard(title: String, value: Double, modifier: Modifier) {
    Column(
        modifier.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(16.dp))
            .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val formatted = if (value < 10) String.format(Locale.getDefault(), "%.1f", value)
        else String.format(Locale.getDefault(), "%.0f", value)
        Text(formatted, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(title, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun BarChart(bars: List<Triple<String, Int, Color>>) {
    val max = (bars.maxOfOrNull { it.second } ?: 0).coerceAtLeast(1)
    Row(
        Modifier.fillMaxWidth().height(200.dp).padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.Bottom,
    ) {
        bars.forEach { (label, count, color) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Bottom) {
                Text("$count", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Box(
                    Modifier.width(48.dp)
                        .height((150 * count / max).dp.coerceAtLeast(2.dp))
                        .background(color, RoundedCornerShape(6.dp)),
                )
                Text(label, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center,
                    modifier = Modifier.width(72.dp).padding(top = 4.dp))
            }
        }
    }
}

@Composable
private fun WeekLineChart(
    points: List<Triple<Date, String, Int>>,
    aspectKeys: List<String>,
    aspectLabels: List<String>,
    colors: List<Color>,
) {
    // Group by aspect key -> ordered 7 daily values.
    val days = points.map { it.first }.distinct().sortedBy { it.time }
    val max = (points.maxOfOrNull { it.third } ?: 0).coerceAtLeast(1)
    val weekdayFmt = remember { SimpleDateFormat("EEE", Locale.getDefault()) }

    Column(Modifier.fillMaxWidth()) {
        Canvas(Modifier.fillMaxWidth().height(200.dp).padding(vertical = 8.dp)) {
            val n = days.size
            if (n < 2) return@Canvas
            val stepX = size.width / (n - 1)
            fun y(v: Int) = size.height - (v.toFloat() / max) * size.height
            aspectKeys.forEachIndexed { ai, key ->
                val series = days.map { d ->
                    points.firstOrNull { it.first == d && it.second == key }?.third ?: 0
                }
                for (i in 0 until n - 1) {
                    drawLine(
                        color = colors[ai],
                        start = Offset(i * stepX, y(series[i])),
                        end = Offset((i + 1) * stepX, y(series[i + 1])),
                        strokeWidth = 4f,
                    )
                }
                series.forEachIndexed { i, v ->
                    drawCircle(colors[ai], radius = 5f, center = Offset(i * stepX, y(v)))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            days.forEach { d ->
                Text(weekdayFmt.format(d), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        // Legend
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            aspectLabels.forEachIndexed { i, label ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).background(colors[i], RoundedCornerShape(50)))
                    Text(" $label", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

/**
 * Counts words and glossary terms whose per-aspect last-remembered date is
 * today. A term's two methods line up with a word's first two: recalling the
 * term itself, and recalling what it means.
 */
private fun countTodayRemembered(
    words: List<VocabWord>,
    entries: List<GlossaryEntry> = emptyList(),
): Map<String, Int> {
    val now = Date()
    fun isToday(d: Date?) = d != null && VocabWord.isSameDay(d, now)
    var word = 0; var translation = 0; var pronunciation = 0
    for (w in words) {
        if (isToday(w.lastWordRemembered)) word++
        if (isToday(w.lastTranslationRemembered)) translation++
        if (isToday(w.lastPronounciationRemembered)) pronunciation++
    }
    for (e in entries) {
        if (isToday(e.lastTermRemembered)) word++
        if (isToday(e.lastDefinitionRemembered)) translation++
    }
    return mapOf("word" to word, "translation" to translation, "pronunciation" to pronunciation)
}

/** Builds 7 days of (date, aspectKey, count): today from the words, earlier from the log. */
private fun buildWeekPoints(daily: List<com.retainic.app.data.DailyStat>, today: Map<String, Int>): List<Triple<Date, String, Int>> {
    val cal = Calendar.getInstance()
    val todayStart = VocabWord.startOfDay(Date())
    val byKey = daily.associateBy { it.date }
    val aspectKeys = listOf("word", "translation", "pronunciation")
    val result = mutableListOf<Triple<Date, String, Int>>()
    for (offset in 6 downTo 0) {
        cal.time = todayStart
        cal.add(Calendar.DAY_OF_YEAR, -offset)
        val day = cal.time
        val stat = byKey[VocabRepository.dayKey(day)]
        for (key in aspectKeys) {
            val value = if (offset == 0) today[key] ?: 0 else when (key) {
                "word" -> stat?.word ?: 0
                "translation" -> stat?.translation ?: 0
                "pronunciation" -> stat?.pronunciation ?: 0
                else -> 0
            }
            result.add(Triple(day, key, value))
        }
    }
    return result
}
