//
//  StatsView.swift
//  Retainic
//
//  Learning statistics: total words memorized and the average pace per
//  day / week / month, aggregated across every list.
//

import SwiftUI
import Combine

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
        } catch {
            errorMessage = error.localizedDescription
        }
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
