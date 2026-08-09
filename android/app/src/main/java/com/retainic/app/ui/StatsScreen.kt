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
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.foundation.Canvas
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.GlossaryEntry
import com.retainic.app.data.GlossaryRepository
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabWord
import kotlinx.coroutines.async
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
/**
 * How fast one kind of item is being memorized: how many of them are done, over
 * the days since the first one was added.
 */
private class Pace(val count: Int, val memorized: Int, createdDates: List<Date>) {
    val startDate: Date? = createdDates.minByOrNull { it.time }
    val activeDays: Int = if (startDate != null) {
        maxOf(1, VocabWord.daysBetween(VocabWord.startOfDay(startDate), VocabWord.startOfDay(Date())) + 1)
    } else 1
    val perDay: Double = memorized.toDouble() / activeDays
    val perWeek: Double = perDay * 7
    val perMonth: Double = perDay * (365.25 / 12)
}

private class LearningStats(allWords: List<VocabWord>, allEntries: List<GlossaryEntry> = emptyList()) {
    val totalWords = allWords.size + allEntries.size
    val totalMemorized = allWords.count { it.isRemembered } + allEntries.count { it.isRemembered }

    // Words and terms are paced separately: each counts from the day its own
    // first one was added, so a glossary started last week isn't judged against
    // months of vocabulary.
    val words = Pace(allWords.size, allWords.count { it.isRemembered }, allWords.mapNotNull { it.createdAt })
    val terms = Pace(allEntries.size, allEntries.count { it.isRemembered }, allEntries.mapNotNull { it.createdAt })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(auth: AuthService, modifier: Modifier = Modifier) {
    var stats by remember { mutableStateOf<LearningStats?>(null) }
    var today by remember { mutableStateOf(mapOf("word" to 0, "translation" to 0, "pronunciation" to 0)) }
    var week by remember { mutableStateOf<List<Triple<Date, String, Int>>>(emptyList()) }
    var glossary by remember { mutableStateOf(GlossaryStats()) }
    var glossaryWeek by remember { mutableStateOf<List<Triple<Date, String, Int>>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(auth.uid) {
        val uid = auth.uid ?: return@LaunchedEffect
        isLoading = true
        try {
            // Everything this screen needs, fetched at once: the words, the
            // glossary terms and the week's tallies don't depend on each other,
            // so waiting for each in turn only added up round trips.
            val allDeferred = async { VocabRepository.fetchAllWords(uid) }
            val entriesDeferred = async { GlossaryRepository.fetchAllEntries(uid) }
            val dailyDeferred = async {
                runCatching { VocabRepository.fetchDailyStats(uid, 7) }.getOrDefault(emptyList())
            }
            val all = allDeferred.await()
            val allEntries = entriesDeferred.await()
            stats = LearningStats(all, allEntries)
            today = countTodayRemembered(all)
            glossary = glossaryStats(allEntries)
            val daily = dailyDeferred.await()
            week = buildWeekPoints(daily, today)
            glossaryWeek = buildGlossaryWeekPoints(daily, glossary)
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
                else -> StatsContent(s, today, week, glossary, glossaryWeek)
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
    glossary: GlossaryStats,
    glossaryWeek: List<Triple<Date, String, Int>>,
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

        // Words practice today (bar chart)
        Text(stringResource(R.string.words_practice_today), style = MaterialTheme.typography.titleMedium)
        BarChart(aspectKeys.mapIndexed { i, k -> Triple(aspectLabels[i], today[k] ?: 0, AspectColors[i]) })
        Text(stringResource(R.string.n_cards_practised, aspectKeys.sumOf { today[it] ?: 0 }),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())

        // Words this week (line chart)
        Text(stringResource(R.string.words_this_week), style = MaterialTheme.typography.titleMedium)
        WeekLineChart(week, aspectKeys, aspectLabels, AspectColors)

        // Glossaries get their own charts: what was practised today, and the
        // week behind it.
        if (glossary.total > 0) {
            Text(stringResource(R.string.glossary_practice_today), style = MaterialTheme.typography.titleMedium)
            BarChart(listOf(
                Triple(stringResource(R.string.term), glossary.termsToday, AspectColors[0]),
                Triple(stringResource(R.string.definition), glossary.definitionsToday, AspectColors[1]),
            ))
            Text(stringResource(R.string.n_cards_practised, glossary.termsToday + glossary.definitionsToday),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())

            // The glossary week is drawn from tallies glossary practice writes
            // for itself, so it only fills in from the day that started.
            Text(stringResource(R.string.glossary_this_week), style = MaterialTheme.typography.titleMedium)
            WeekLineChart(
                glossaryWeek,
                listOf("glossaryTerm", "glossaryDefinition"),
                listOf(stringResource(R.string.term), stringResource(R.string.definition)),
                AspectColors,
            )
        }

        // Average pace, words and terms apart
        if (stats.words.count > 0) PaceSection(stringResource(R.string.words_average_pace), stats.words)
        if (stats.terms.count > 0) PaceSection(stringResource(R.string.terms_average_pace), stats.terms)
    }
}

/** One kind's pace, with the stretch of learning it was measured over. */
@Composable
private fun PaceSection(title: String, pace: Pace) {
    Text(title, style = MaterialTheme.typography.titleMedium)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        PaceCard(stringResource(R.string.per_day), pace.perDay, Modifier.weight(1f))
        PaceCard(stringResource(R.string.per_week), pace.perWeek, Modifier.weight(1f))
        PaceCard(stringResource(R.string.per_month), pace.perMonth, Modifier.weight(1f))
    }
    pace.startDate?.let { start ->
        val since = DateFormat.getDateInstance(DateFormat.MEDIUM, Locale.getDefault()).format(start)
        Text(stringResource(R.string.based_on_days, pace.activeDays, since),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
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

/** Every chart is drawn in a box this tall, so the dashboard lines up. */
private val ChartHeight = 220.dp

/** The bar area of a bar chart, below the value labels and above the names. */
private val BarPlotHeight = 150.dp

/**
 * The values to rule a chart at: the finest round step that keeps it to five
 * lines or fewer, so the gaps are easy to read off. A chart whose tallest value
 * is 3 gets lines at 1, 2 and 3; one reaching 50 gets 10, 20, 30, 40, 50.
 */
private fun guideValues(max: Int): List<Int> {
    val step = listOf(1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000)
        .firstOrNull { (max + it - 1) / it <= 5 } ?: 1000
    return generateSequence(step) { it + step }.takeWhile { it <= max }.toList()
}

/**
 * Dashed guide lines behind a chart, so a bar or a point can be read against a
 * value instead of eyeballed. [plotHeight] is the height the data is drawn in,
 * measured up from the bottom of this canvas; null means the whole canvas.
 */
@Composable
private fun GuideLines(max: Int, plotHeight: Dp? = null, modifier: Modifier = Modifier) {
    val color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
    Canvas(modifier) {
        val plot = plotHeight?.toPx() ?: size.height
        val dash = PathEffect.dashPathEffect(floatArrayOf(8f, 8f))
        for (value in guideValues(max)) {
            val y = size.height - plot * (value.toFloat() / max)
            drawLine(color, Offset(0f, y), Offset(size.width, y), strokeWidth = 2f, pathEffect = dash)
        }
    }
}

@Composable
private fun BarChart(bars: List<Triple<String, Int, Color>>) {
    val max = (bars.maxOfOrNull { it.second } ?: 0).coerceAtLeast(1)
    Column(Modifier.fillMaxWidth().height(ChartHeight).padding(vertical = 8.dp)) {
        // The bars and their names are separate rows, so the bottom of this box
        // is the line the bars stand on — the one the guide lines measure from.
        Box(Modifier.fillMaxWidth().weight(1f)) {
            GuideLines(max, BarPlotHeight, Modifier.matchParentSize())
            // Each bar takes an equal share of the width, and each name below
            // takes the same share — so they stay centred on each other, and a
            // long name like "Pronunciation" has the whole share to sit in
            // rather than a box narrower than the word.
            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.Bottom) {
                bars.forEach { (_, count, color) ->
                    Column(
                        Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Bottom,
                    ) {
                        Text("$count", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Box(
                            Modifier.width(48.dp)
                                .height((BarPlotHeight * (count.toFloat() / max)).coerceAtLeast(2.dp))
                                .background(color, RoundedCornerShape(6.dp)),
                        )
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            bars.forEach { (label, _, _) ->
                Text(
                    label,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f).padding(top = 4.dp, start = 2.dp, end = 2.dp),
                )
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

    val guideColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)

    Column(Modifier.fillMaxWidth()) {
        Canvas(Modifier.fillMaxWidth().height(ChartHeight).padding(vertical = 8.dp)) {
            val n = days.size
            if (n < 2) return@Canvas
            val stepX = size.width / (n - 1)
            fun y(v: Int) = size.height - (v.toFloat() / max) * size.height
            // Ruled first, so the week's lines are drawn over the guides.
            val dash = PathEffect.dashPathEffect(floatArrayOf(8f, 8f))
            for (value in guideValues(max)) {
                drawLine(guideColor, Offset(0f, y(value)), Offset(size.width, y(value)),
                    strokeWidth = 2f, pathEffect = dash)
            }
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
 * What a user's glossary practice looks like today, for the charts glossaries
 * get to themselves. [total] is how many terms there are at all, which decides
 * whether those charts are worth showing.
 */
data class GlossaryStats(
    val total: Int = 0,
    val termsToday: Int = 0,
    val definitionsToday: Int = 0,
)

private fun glossaryStats(entries: List<GlossaryEntry>): GlossaryStats {
    val now = Date()
    fun isToday(d: Date?) = d != null && VocabWord.isSameDay(d, now)
    var termsToday = 0; var definitionsToday = 0
    for (e in entries) {
        if (isToday(e.lastTermRemembered)) termsToday++
        // Every definition is a card of its own, so each one recalled today
        // counts on its own.
        definitionsToday += e.definitionList.count { isToday(it.lastRemembered) }
    }
    return GlossaryStats(entries.size, termsToday, definitionsToday)
}

/**
 * Counts words whose per-aspect last-remembered date is today. Glossary terms
 * are counted apart, in [GlossaryStats], so the two sets of charts don't count
 * the same practice twice.
 */
private fun countTodayRemembered(words: List<VocabWord>): Map<String, Int> {
    val now = Date()
    fun isToday(d: Date?) = d != null && VocabWord.isSameDay(d, now)
    var word = 0; var translation = 0; var pronunciation = 0
    for (w in words) {
        if (isToday(w.lastWordRemembered)) word++
        if (isToday(w.lastTranslationRemembered)) translation++
        if (isToday(w.lastPronounciationRemembered)) pronunciation++
    }
    return mapOf("word" to word, "translation" to translation, "pronunciation" to pronunciation)
}

/**
 * Builds 7 days of (date, glossary aspect key, count) from the tallies glossary
 * practice writes for itself. Today comes from the terms, as it does in the
 * combined chart.
 */
private fun buildGlossaryWeekPoints(
    daily: List<com.retainic.app.data.DailyStat>,
    glossary: GlossaryStats,
): List<Triple<Date, String, Int>> {
    val cal = Calendar.getInstance()
    val todayStart = VocabWord.startOfDay(Date())
    val byKey = daily.associateBy { it.date }
    val result = mutableListOf<Triple<Date, String, Int>>()
    for (offset in 6 downTo 0) {
        cal.time = todayStart
        cal.add(Calendar.DAY_OF_YEAR, -offset)
        val day = cal.time
        val stat = byKey[VocabRepository.dayKey(day)]
        result.add(Triple(day, "glossaryTerm",
            if (offset == 0) glossary.termsToday else stat?.glossaryTerm ?: 0))
        result.add(Triple(day, "glossaryDefinition",
            if (offset == 0) glossary.definitionsToday else stat?.glossaryDefinition ?: 0))
    }
    return result
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
            // A day's shared tally covers both kinds of practice, so the word
            // series is what's left once the glossary's own tally is taken out.
            // Days logged before glossaries tallied separately have nothing to
            // take out, and read as before.
            val value = if (offset == 0) today[key] ?: 0 else when (key) {
                "word" -> maxOf(0, (stat?.word ?: 0) - (stat?.glossaryTerm ?: 0))
                "translation" -> maxOf(0, (stat?.translation ?: 0) - (stat?.glossaryDefinition ?: 0))
                "pronunciation" -> stat?.pronunciation ?: 0
                else -> 0
            }
            result.add(Triple(day, key, value))
        }
    }
    return result
}
