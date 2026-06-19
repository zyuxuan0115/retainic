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

    init(words: [VocabWord]) {
        totalWords = words.count
        let memorized = words.filter { $0.isMemorized }
        totalMemorized = memorized.count

        let now = Date()
        let cal = Calendar.current
        let start = words.map(\.createdAt).min()
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

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var stats: LearningStats?
    /// Past-days history (today is computed from the words instead).
    @Published var dailyStats: [DailyStat] = []
    /// Today's remembered counts per aspect, derived from the words themselves.
    @Published var todayRemembered: [String: Int] = [:]
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
            stats = LearningStats(words: all)
            todayRemembered = Self.countTodayRemembered(all)
            dailyStats = (try? await VocabRepository.fetchDailyStats(uid: uid, days: 7)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Counts words across all lists whose per-aspect last-remembered date is today.
    private static func countTodayRemembered(_ words: [VocabWord]) -> [String: Int] {
        let cal = Calendar.current
        func isToday(_ date: Date?) -> Bool { date.map(cal.isDateInToday) ?? false }
        var counts = ["word": 0, "translation": 0, "pronunciation": 0]
        for word in words {
            if isToday(word.lastWordRemembered) { counts["word", default: 0] += 1 }
            if isToday(word.lastTranslationRemembered) { counts["translation", default: 0] += 1 }
            if isToday(word.lastPronounciationRemembered) { counts["pronunciation", default: 0] += 1 }
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
            .alert("Something went wrong".localized(preferredLanguage), isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK".localized(preferredLanguage), role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private func content(_ stats: LearningStats) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                totalCard(stats)

                todayChart
                weekChart

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
            Text("Remembered today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Chart(todayBars) { bar in
                BarMark(
                    x: .value("Type", bar.label),
                    y: .value("Remembered", bar.count)
                )
                .foregroundStyle(by: .value("Type", bar.label))
                .annotation(position: .top) {
                    Text("\(bar.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale(domain: styleDomain, range: styleRange)
            .chartLegend(.hidden)
            .frame(height: 200)
        }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Chart(weekPoints) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Remembered", point.count)
                )
                .foregroundStyle(by: .value("Type", point.aspect))
                .symbol(by: .value("Type", point.aspect))
            }
            .chartForegroundStyleScale(domain: styleDomain, range: styleRange)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 240)
        }
    }

    private func totalCard(_ stats: LearningStats) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("\(stats.totalMemorized)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text("words memorized")
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
