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

/// Aggregate learning statistics computed from every word the user has.
struct LearningStats {
    let totalWords: Int
    let totalMemorized: Int
    let activeDays: Int
    let startDate: Date?
    let perDay: Double
    let perWeek: Double
    let perMonth: Double

    /// Glossary practice records the same daily tallies as list practice, so the
    /// totals cover both a user's words and their glossary terms.
    init(words: [VocabWord], entries: [GlossaryEntry] = []) {
        totalWords = words.count + entries.count
        // Fully memorized = recalled enough times in every aspect (remember_final:
        // 8× word, 10× translation, 7× pronunciation; for a term, 5× the term
        // and 5× each of its definitions).
        totalMemorized = words.filter { $0.isRemembered }.count
            + entries.filter { $0.isRemembered }.count

        let now = Date()
        let cal = Calendar.current
        let start = (words.map(\.createdAt) + entries.map(\.createdAt)).min()
        startDate = start

        // Days the user has been learning, counting the first day.
        if let start {
            let dayCount = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: start),
                to: cal.startOfDay(for: now)
            ).day ?? 0
            activeDays = max(1, dayCount + 1)
        } else {
            activeDays = 1
        }

        let total = Double(totalMemorized)
        let days = Double(activeDays)
        perDay = total / days
        perWeek = perDay * 7
        perMonth = perDay * (365.25 / 12)
    }
}

/// How far a user's glossary terms have come, for the charts glossaries get to
/// themselves. A term is memorized once its term side and every one of its
/// definitions have had their five recalls; anything with at least one recall
/// behind it is under way, and the rest hasn't been started.
struct GlossaryStats {
    var total = 0
    var memorized = 0
    var started = 0
    var untouched = 0
    var termsToday = 0
    var definitionsToday = 0

    init() {}

    init(entries: [GlossaryEntry]) {
        let cal = Calendar.current
        func isToday(_ date: Date?) -> Bool { date.map(cal.isDateInToday) ?? false }
        total = entries.count
        for entry in entries {
            let definitions = entry.definitionList
            if isToday(entry.lastTermRemembered) { termsToday += 1 }
            // Every definition is a card of its own, so each one recalled today
            // counts on its own.
            definitionsToday += definitions.filter { isToday($0.lastRemembered) }.count
            let recalls = (entry.timesTermCorrect ?? 0) + definitions.reduce(0) { $0 + $1.timesCorrect }
            if entry.isRemembered { memorized += 1 }
            else if recalls > 0 { started += 1 }
            else { untouched += 1 }
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

                // Glossaries get their own two charts: how far the terms have
                // come, and what was practised today.
                if vm.glossary.total > 0 {
                    glossaryProgressChart
                    glossaryTodayChart
                    glossaryWeekChart
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Average pace")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        averageCard(title: "Per day", value: stats.perDay)
                        averageCard(title: "Per week", value: stats.perWeek)
                        averageCard(title: "Per month", value: stats.perMonth)
                    }
                    // titles above are LocalizedStringKey literals
                }

                if let start = stats.startDate {
                    let since = start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
                    Text("Based on \(stats.activeDays) days of learning since \(since).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
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
            Text("Words today")
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

    private var glossaryProgressBars: [AspectBar] {
        [
            AspectBar(key: "memorized", label: "Memorized".localized(preferredLanguage), count: vm.glossary.memorized),
            AspectBar(key: "started", label: "In progress".localized(preferredLanguage), count: vm.glossary.started),
            AspectBar(key: "untouched", label: "Not started".localized(preferredLanguage), count: vm.glossary.untouched),
        ]
    }

    private var glossaryTodayBars: [AspectBar] {
        [
            AspectBar(key: "term", label: "Term".localized(preferredLanguage), count: vm.glossary.termsToday),
            AspectBar(key: "definition", label: "Definition".localized(preferredLanguage), count: vm.glossary.definitionsToday),
        ]
    }

    private var glossaryProgressChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glossary terms")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            barChart(glossaryProgressBars, labels: glossaryProgressBars.map(\.label))
            Text("\(vm.glossary.memorized) of \(vm.glossary.total) terms memorized")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
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
