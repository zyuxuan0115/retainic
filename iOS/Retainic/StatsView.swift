//
//  StatsView.swift
//  Retainic
//
//  Learning statistics: total words memorized and the average pace per
//  day / week / month, aggregated across every list.
//

import SwiftUI
import Combine
import Charts

/// One bar in the "remembered today" chart.
private struct AspectBar: Identifiable {
    let key: String
    let label: String
    let count: Int
    var id: String { key }
}

/// Every chart is drawn in a box this tall, so the dashboard lines up.
private let chartHeight: CGFloat = 220

/// One point in the weekly trend chart.
private struct DayAspectPoint: Identifiable {
    let id = UUID()
    let date: Date
    let aspect: String
    let count: Int
}

/// How fast one kind of item is being memorized: how many of them are done,
/// over the days since the first one was added.
struct Pace {
    var count = 0
    var memorized = 0
    var activeDays = 1
    var startDate: Date?
    var perDay: Double = 0
    var perWeek: Double = 0
    var perMonth: Double = 0

    init() {}

    init(count: Int, memorized: Int, createdDates: [Date]) {
        self.count = count
        self.memorized = memorized
        let start = createdDates.min()
        startDate = start
        // Days the user has been learning this kind, counting the first day.
        if let start {
            let cal = Calendar.current
            let dayCount = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: start),
                to: cal.startOfDay(for: Date())
            ).day ?? 0
            activeDays = max(1, dayCount + 1)
        }
        perDay = Double(memorized) / Double(activeDays)
        perWeek = perDay * 7
        perMonth = perDay * (365.25 / 12)
    }
}

/// Aggregate learning statistics computed from every word and term the user has.
struct LearningStats {
    let totalWords: Int
    let totalMemorized: Int
    /// Words and terms are paced separately: each counts from the day its own
    /// first one was added, so a glossary started last week isn't judged
    /// against months of vocabulary.
    let words: Pace
    let terms: Pace

    /// Glossary practice records the same daily tallies as list practice, so the
    /// totals cover both a user's words and their glossary terms.
    init(words allWords: [VocabWord], entries: [GlossaryEntry] = []) {
        totalWords = allWords.count + entries.count
        // Fully memorized = recalled enough times in every aspect (remember_final:
        // 8× word, 10× translation, 7× pronunciation; for a term, 5× the term
        // and 5× each of its definitions).
        totalMemorized = allWords.filter { $0.isRemembered }.count
            + entries.filter { $0.isRemembered }.count

        words = Pace(count: allWords.count,
                     memorized: allWords.filter { $0.isRemembered }.count,
                     createdDates: allWords.map(\.createdAt))
        terms = Pace(count: entries.count,
                     memorized: entries.filter { $0.isRemembered }.count,
                     createdDates: entries.map(\.createdAt))
    }
}

/// What a user's glossary practice looks like today, for the charts glossaries
/// get to themselves. `total` is how many terms there are at all, which decides
/// whether those charts are worth showing.
struct GlossaryStats {
    var total = 0
    var termsToday = 0
    var definitionsToday = 0

    init() {}

    init(entries: [GlossaryEntry]) {
        let cal = Calendar.current
        func isToday(_ date: Date?) -> Bool { date.map(cal.isDateInToday) ?? false }
        total = entries.count
        for entry in entries {
            if isToday(entry.lastTermRemembered) { termsToday += 1 }
            // Every definition is a card of its own, so each one recalled today
            // counts on its own.
            definitionsToday += entry.definitionList.filter { isToday($0.lastRemembered) }.count
        }
    }
}

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var stats: LearningStats?
    /// Past-days history (today is computed from the words instead).
    @Published var dailyStats: [DailyStat] = []
    /// Today's remembered counts per aspect, derived from the words themselves.
    @Published var todayRemembered: [String: Int] = [:]
    /// Glossary-only counts, for the glossary charts.
    @Published var glossary = GlossaryStats()
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(uid: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let lists = try await VocabRepository.fetchLists(uid: uid)
            var all: [VocabWord] = []
            for list in lists {
                guard let listId = list.id else { continue }
                all += try await VocabRepository.fetchWords(uid: uid, listId: listId)
            }
            let glossaries = try await GlossaryRepository.fetchGlossaries(uid: uid)
            var allEntries: [GlossaryEntry] = []
            for glossary in glossaries {
                guard let glossaryId = glossary.id else { continue }
                allEntries += try await GlossaryRepository.fetchEntries(uid: uid, glossaryId: glossaryId)
            }
            stats = LearningStats(words: all, entries: allEntries)
            todayRemembered = Self.countTodayRemembered(all, entries: allEntries)
            glossary = GlossaryStats(entries: allEntries)
            dailyStats = (try? await VocabRepository.fetchDailyStats(uid: uid, days: 7)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Counts words and glossary terms whose per-aspect last-remembered date is
    /// today. A term's two methods line up with a word's first two: recalling
    /// the term itself, and recalling what it means.
    private static func countTodayRemembered(_ words: [VocabWord], entries: [GlossaryEntry] = []) -> [String: Int] {
        let cal = Calendar.current
        func isToday(_ date: Date?) -> Bool { date.map(cal.isDateInToday) ?? false }
        var counts = ["word": 0, "translation": 0, "pronunciation": 0]
        for word in words {
            if isToday(word.lastWordRemembered) { counts["word", default: 0] += 1 }
            if isToday(word.lastTranslationRemembered) { counts["translation", default: 0] += 1 }
            if isToday(word.lastPronounciationRemembered) { counts["pronunciation", default: 0] += 1 }
        }
        for entry in entries {
            if isToday(entry.lastTermRemembered) { counts["word", default: 0] += 1 }
            // Every definition is a card of its own, so each one recalled today
            // counts — the same way the daily tallies were written in practice.
            counts["translation", default: 0] += entry.definitionList
                .filter { isToday($0.lastRemembered) }.count
        }
        return counts
    }
}

struct StatsView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var vm = StatsViewModel()
    @Environment(\.locale) private var locale
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.stats == nil {
                    ProgressView("Loading…")
                } else if let stats = vm.stats, stats.totalWords > 0 {
                    content(stats)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Statistics".localized(preferredLanguage))
            .task(id: auth.uid) {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .refreshable {
                if let uid = auth.uid { await vm.load(uid: uid) }
            }
            .repositoryErrorAlert($vm.errorMessage, language: preferredLanguage)
        }
    }

    private func content(_ stats: LearningStats) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                totalCard(stats)

                todayChart
                weekChart

                // Glossaries get their own charts: what was practised today,
                // and the week behind it.
                if vm.glossary.total > 0 {
                    glossaryTodayChart
                    glossaryWeekChart
                }

                if stats.words.count > 0 { paceSection("Words average pace", stats.words) }
                if stats.terms.count > 0 { paceSection("Terms average pace", stats.terms) }
            }
            .padding()
        }
    }

    // MARK: - Charts

    private var aspectKeys: [String] { ["word", "translation", "pronunciation"] }

    private func aspectLabel(_ key: String) -> String {
        switch key {
        case "word": return "Word".localized(preferredLanguage)
        case "translation": return "Translation".localized(preferredLanguage)
        case "pronunciation": return "Pronunciation".localized(preferredLanguage)
        default: return key
        }
    }

    private func count(_ stat: DailyStat?, _ key: String) -> Int {
        guard let stat else { return 0 }
        switch key {
        case "word": return stat.word ?? 0
        case "translation": return stat.translation ?? 0
        case "pronunciation": return stat.pronunciation ?? 0
        default: return 0
        }
    }

    private var todayBars: [AspectBar] {
        aspectKeys.map { AspectBar(key: $0, label: aspectLabel($0), count: vm.todayRemembered[$0] ?? 0) }
    }

    private var weekPoints: [DayAspectPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var byKey: [String: DailyStat] = [:]
        for stat in vm.dailyStats { byKey[stat.date] = stat }
        var points: [DayAspectPoint] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let stat = byKey[VocabRepository.dayKey(day)]
            for key in aspectKeys {
                // Today is derived from the words; earlier days from the log.
                let value = offset == 0 ? (vm.todayRemembered[key] ?? 0) : count(stat, key)
                points.append(DayAspectPoint(date: day, aspect: aspectLabel(key), count: value))
            }
        }
        return points
    }

    private var styleDomain: [String] { aspectKeys.map(aspectLabel) }
    private let styleRange: [Color] = [.blue, .green, .orange]

    private var todayChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Words practice today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            barChart(todayBars, labels: styleDomain)
        }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Words this week")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            lineChart(weekPoints, labels: styleDomain)
        }
    }

    /// The weekly trend chart, over whichever series it's given.
    private func lineChart(_ points: [DayAspectPoint], labels: [String]) -> some View {
        Chart(points) { point in
            LineMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Remembered", point.count)
            )
            .foregroundStyle(by: .value("Type", point.aspect))
            .symbol(by: .value("Type", point.aspect))
        }
        .chartForegroundStyleScale(domain: labels, range: Array(styleRange.prefix(labels.count)))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: chartHeight)
    }

    /// The glossary's own week, from the tallies glossary practice writes for
    /// itself. Today comes from the terms, as it does in the combined chart.
    private var glossaryWeekPoints: [DayAspectPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var byKey: [String: DailyStat] = [:]
        for stat in vm.dailyStats { byKey[stat.date] = stat }
        let series = [
            ("term", "Term".localized(preferredLanguage)),
            ("definition", "Definition".localized(preferredLanguage)),
        ]
        var points: [DayAspectPoint] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let stat = byKey[VocabRepository.dayKey(day)]
            for (key, label) in series {
                let logged = key == "term" ? (stat?.glossaryTerm ?? 0) : (stat?.glossaryDefinition ?? 0)
                let todayCount = key == "term" ? vm.glossary.termsToday : vm.glossary.definitionsToday
                points.append(DayAspectPoint(date: day, aspect: label, count: offset == 0 ? todayCount : logged))
            }
        }
        return points
    }

    private var glossaryWeekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glossary this week")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            lineChart(glossaryWeekPoints, labels: glossaryTodayBars.map(\.label))
        }
    }

    private var glossaryTodayBars: [AspectBar] {
        [
            AspectBar(key: "term", label: "Term".localized(preferredLanguage), count: vm.glossary.termsToday),
            AspectBar(key: "definition", label: "Definition".localized(preferredLanguage), count: vm.glossary.definitionsToday),
        ]
    }

    private var glossaryTodayChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glossary practice today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            barChart(glossaryTodayBars, labels: glossaryTodayBars.map(\.label))
            Text("\(vm.glossary.termsToday + vm.glossary.definitionsToday) cards practised")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// The same bar chart the "Words today" chart draws, over whichever
    /// bars it's given.
    private func barChart(_ bars: [AspectBar], labels: [String]) -> some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Type", bar.label),
                y: .value("Remembered", bar.count)
            )
            .foregroundStyle(by: .value("Type", bar.label))
            .annotation(position: .top) {
                Text("\(bar.count)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartForegroundStyleScale(domain: labels, range: Array(styleRange.prefix(labels.count)))
        .chartLegend(.hidden)
        .frame(height: chartHeight)
    }

    /// One kind's pace, with the stretch of learning it was measured over.
    private func paceSection(_ title: LocalizedStringKey, _ pace: Pace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                averageCard(title: "Per day", value: pace.perDay)
                averageCard(title: "Per week", value: pace.perWeek)
                averageCard(title: "Per month", value: pace.perMonth)
            }

            if let start = pace.startDate {
                let since = start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
                Text("Based on \(pace.activeDays) days of learning since \(since).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func totalCard(_ stats: LearningStats) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("\(stats.totalMemorized)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text("words and terms memorized")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("out of \(stats.totalWords) total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func averageCard(title: LocalizedStringKey, value: Double) -> some View {
        VStack(spacing: 6) {
            Text(formatted(value))
                .font(.title2.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Stats Yet", systemImage: "chart.bar")
        } description: {
            Text("Add words and practice them. Once you've memorized some, your progress shows up here.")
        }
    }

    /// One decimal for small rates, whole numbers otherwise.
    private func formatted(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value.rounded())
    }
}

#Preview {
    StatsView()
        .environmentObject(AuthService())
}
