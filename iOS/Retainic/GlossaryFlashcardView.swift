//
//  GlossaryFlashcardView.swift
//  Retainic
//
//  Flip-card practice for a glossary. Same session flow as FlashcardView (and
//  the same card), but over terms and definitions: two methods instead of
//  three, and no audio.
//
//  A term that means several things is one card per meaning when the definition
//  is shown first — each definition has its own schedule — and a single card
//  the other way round, revealing them all.
//

import SwiftUI

/// A card in the running session together with the method it's shown in, and —
/// when the definition is the prompt — which definition is being practised.
private struct GlossarySessionItem {
    var card: GlossaryPracticeCard
    let aspect: GlossaryAspect
    var definitionIndex: Int = 0
}

struct GlossaryFlashcardView: View {
    let cards: [GlossaryPracticeCard]
    /// The glossary's review direction. One-way glossaries only ever show the
    /// term, so that is the only method this session offers.
    var direction: GlossaryReviewDirection = .both

    @EnvironmentObject private var auth: AuthService

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    @State private var session: [GlossarySessionItem] = []
    @State private var index = 0
    @State private var isFlipped = false
    @State private var selectedAspects: Set<GlossaryAspect> = [.term]
    @State private var correctCount = 0
    /// Distinct cards in this session (missed ones are re-queued, so
    /// `session.count` grows; this stays the count of unique cards).
    @State private var totalCards = 0
    @State private var isFinished = false
    @State private var dueOnly = true

    var body: some View {
        Group {
            if cards.isEmpty {
                emptyState
            } else if session.isEmpty {
                setupView
            } else if isFinished {
                summaryView
            } else {
                practiceView
            }
        }
        .navigationTitle("Practice".localized(preferredLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !session.isEmpty && !isFinished {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End", role: .cancel) { isFinished = true }
                }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing to Practice",
            systemImage: "rectangle.on.rectangle.angled",
            description: Text("Add some terms to a glossary first, then come back to review them.")
        )
    }

    /// Number of aspect-cards the current settings would include.
    private var dueCount: Int { deck(shuffled: false).count }

    private func toggleAspect(_ aspect: GlossaryAspect) {
        if selectedAspects.contains(aspect) {
            selectedAspects.remove(aspect)
        } else {
            selectedAspects.insert(aspect)
        }
    }

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Ready to practice?")
                    .font(.title2.bold())
                Text(dueCount > 0
                     ? "\(dueCount) cards due for review."
                     : "You finished your daily assignment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Daily assignment", isOn: $dueOnly)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Show first")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(direction.aspects) { aspect in
                        Button {
                            toggleAspect(aspect)
                        } label: {
                            HStack {
                                Image(systemName: selectedAspects.contains(aspect) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedAspects.contains(aspect) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                Text(aspect.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)

            Button {
                startSession()
            } label: {
                Text("Start Session")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(dueCount == 0)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private var practiceView: some View {
        let item = session[index]
        let entry = item.card.entry
        let texts = entry.definitionTexts
        // The front is a bare prompt (the term, or one of its definitions); the
        // answer side always reveals the whole entry — the term with everything
        // it can mean.
        let prompt = item.aspect == .definition
            ? (texts.indices.contains(item.definitionIndex) ? texts[item.definitionIndex] : "")
            : entry.term
        let answer = texts.count > 1
            ? texts.map { "• \($0)" }.joined(separator: "\n")
            : (texts.first ?? "")
        return VStack(spacing: 24) {
            ProgressView(value: Double(index), total: Double(session.count))
                .padding(.top)
            Text("\(index + 1) of \(session.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            CardView(
                prompt: prompt,
                term: entry.term,
                translation: answer,
                notes: entry.notes,
                isFlipped: isFlipped
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isFlipped.toggle()
                }
            }

            Spacer()

            if isFlipped {
                HStack(spacing: 16) {
                    answerButton(title: "Practice Again", systemImage: "arrow.counterclockwise", tint: .orange) {
                        handleAnswer(correct: false)
                    }
                    answerButton(title: "Got It", systemImage: "checkmark", tint: .green) {
                        handleAnswer(correct: true)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tap the card to reveal the answer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
            }
        }
        .padding()
        .animation(.easeInOut, value: isFlipped)
    }

    private var summaryView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Session Complete!")
                .font(.title.bold())
            Text("You got \(correctCount) of \(totalCards) right.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                resetToSetup()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Components

    private func answerButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
    }

    // MARK: - Session logic

    /// The session items one card contributes to a method: in the daily
    /// assignment that method must be due; in free practice every unmemorized
    /// term counts. Shown a definition, each definition is a card of its own.
    private func items(for card: GlossaryPracticeCard, aspect: GlossaryAspect) -> [GlossarySessionItem] {
        let entry = card.entry
        if aspect == .term {
            let include = dueOnly ? entry.isTermDue() : entry.remember_final != true
            return include ? [GlossarySessionItem(card: card, aspect: aspect)] : []
        }
        let indexes = dueOnly
            ? entry.dueDefinitionIndexes()
            : (entry.remember_final != true ? Array(entry.definitionList.indices) : [])
        return indexes.map { GlossarySessionItem(card: card, aspect: aspect, definitionIndex: $0) }
    }

    private func deck(shuffled: Bool = true) -> [GlossarySessionItem] {
        let aspects = selectedAspects.intersection(direction.aspects)
        guard !aspects.isEmpty else { return [] }
        var items: [GlossarySessionItem] = []
        for aspect in aspects {
            for card in cards {
                items.append(contentsOf: self.items(for: card, aspect: aspect))
            }
        }
        return shuffled ? items.shuffled() : items
    }

    private func startSession() {
        let deck = deck()
        guard !deck.isEmpty else { return }
        session = deck
        totalCards = deck.count
        index = 0
        correctCount = 0
        isFlipped = false
        isFinished = false
    }

    private func handleAnswer(correct: Bool) {
        var item = session[index]
        // Progress is only recorded for the daily assignment; free practice
        // doesn't affect schedules or stats.
        if dueOnly {
            if correct {
                item.card.entry.markCorrect(aspect: item.aspect, definitionIndex: item.definitionIndex,
                                            direction: direction)
                recordDailyStat(aspect: item.aspect)
            } else {
                item.card.entry.markIncorrect(aspect: item.aspect)
            }
            session[index] = item
            // An entry can be queued for both methods; keep its copies in sync
            // so one method's save doesn't clobber the other's stats.
            syncEntry(item.card.entry)
            persist(item.card)
        }
        if correct {
            correctCount += 1
        } else {
            // Not remembered: move on, but re-queue it (same method) for review.
            session.append(item)
        }
        advance()
    }

    private func syncEntry(_ entry: GlossaryEntry) {
        for i in session.indices where session[i].card.entry.id == entry.id {
            session[i].card.entry = entry
        }
    }

    private func persist(_ card: GlossaryPracticeCard) {
        guard let uid = auth.uid else { return }
        Task { try? await GlossaryRepository.updateEntry(uid: uid, glossaryId: card.glossaryId, entry: card.entry) }
    }

    /// Glossary practice shares the daily tallies with list practice, so the
    /// Statistics charts count both.
    private func recordDailyStat(aspect: GlossaryAspect) {
        guard let uid = auth.uid else { return }
        Task {
            try? await VocabRepository.recordRemembered(
                uid: uid, aspect: aspect.dailyAspect, glossaryAspect: aspect.rawValue)
        }
    }

    private func advance() {
        withAnimation { isFlipped = false }
        if index + 1 < session.count {
            index += 1
        } else {
            isFinished = true
        }
    }

    private func resetToSetup() {
        session = []
        index = 0
        correctCount = 0
        isFlipped = false
        isFinished = false
    }
}
