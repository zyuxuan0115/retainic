//
//  FlashcardView.swift
//  Retainic
//
//  Flip-card practice across one or more lists, driven by the Leitner boxes.
//  Review results are persisted back to Firestore.
//

import SwiftUI

/// What the front of the card shows before flipping.
enum FrontMode: String, CaseIterable, Identifiable {
    case term, translation, pronunciation
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .term: return "Word"
        case .translation: return "Translation"
        case .pronunciation: return "Audio"
        }
    }

    /// Which memory aspect this practice mode tracks, used for per-word stats and
    /// the per-aspect daily "remembered today" check. The Show First option name
    /// matches the aspect: Translation → translation, Audio → pronunciation, and
    /// Word → spelling.
    var memoryAspect: String {
        switch self {
        case .term: return "spelling"
        case .translation: return "translation"
        case .pronunciation: return "pronunciation"
        }
    }
}

/// A card in the running session together with the mode it's shown in. With
/// multi-select, different cards in one session can use different modes.
private struct SessionItem {
    var card: PracticeCard
    let mode: FrontMode
    /// Index into `word.factValues`; nil for the non-text pronunciation prompt.
    let promptIndex: Int?
}

struct FlashcardView: View {
    let cards: [PracticeCard]
    /// Language of the words being studied (the `term` side), from the list.
    /// Determines whether the reading is pinyin (Chinese) or hiragana (Japanese).
    let learningLanguage: String
    /// Whether the list falls back to a synthesized voice for words without a
    /// recording — so pronunciation practice can include them too.
    let ttsEnabled: Bool

    @EnvironmentObject private var auth: AuthService
    @ObservedObject private var playback = AudioPlaybackStore.shared

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault

    @State private var session: [SessionItem] = []
    @State private var index = 0
    @State private var isFlipped = false
    @State private var selectedModes: Set<FrontMode> = [.term]
    @State private var correctCount = 0
    /// Distinct words in this session (missed words are re-queued, so
    /// `session.count` grows; this stays the count of unique words).
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
                    Button("End", role: .cancel) { endSession() }
                }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing to Practice",
            systemImage: "rectangle.on.rectangle.angled",
            description: Text("Add some words to a list first, then come back to review them.")
        )
    }

    /// Number of aspect-cards the current settings would include.
    private var dueCount: Int {
        selectedModes.reduce(0) { sum, mode in
            sum + cards.filter { includes($0, mode: mode) }.count
        }
    }

    /// In pronunciation mode the audio button is the prompt (front); in the
    /// other modes it's revealed with the answer (back).
    private func showAudioButton(_ mode: FrontMode) -> Bool {
        mode == .pronunciation ? !isFlipped : isFlipped
    }

    /// The active-playback key for a word's pronunciation: its recording path, or
    /// a TTS key when the list falls back to a synthesized voice — nil for
    /// neither.
    private func pronunciationKey(for word: VocabWord) -> String? {
        if let path = word.audioPath { return path }
        if ttsEnabled { return AudioPlaybackStore.ttsKey(word.term) }
        return nil
    }

    private func activatePronunciation(for word: VocabWord) {
        if let path = word.audioPath {
            playback.toggle(path: path)
        } else if ttsEnabled {
            playback.toggleSpeak(text: word.term, language: learningLanguage)
        }
    }

    private func toggleMode(_ mode: FrontMode) {
        if selectedModes.contains(mode) {
            selectedModes.remove(mode)
        } else {
            selectedModes.insert(mode)
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
                    ForEach(FrontMode.allCases) { mode in
                        Button {
                            toggleMode(mode)
                        } label: {
                            HStack {
                                Image(systemName: selectedModes.contains(mode) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedModes.contains(mode) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                Text(mode.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if selectedModes.contains(.pronunciation) && !ttsEnabled {
                        Text("Audio is only used for words with a recorded pronunciation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .disabled(deck().isEmpty)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private var practiceView: some View {
        let mode = session[index].mode
        let word = session[index].card.word
        let facts = word.factValues
        let promptIndex = session[index].promptIndex
        let prompt = promptIndex.flatMap { facts.indices.contains($0) ? facts[$0] : nil } ?? word.term
        let answerTerm = mode == .pronunciation || promptIndex != 0 ? word.term : nil
        let answerFacts = word.translationValues.enumerated().compactMap { factIndex, fact in
            mode == .pronunciation || factIndex + 1 != promptIndex ? fact : nil
        }
        let termReading = reading(for: word)
        let posLabels = word.partOfSpeechValues.map { $0.label(for: preferredLanguage) }
        return VStack(spacing: 24) {
            ProgressView(value: Double(index), total: Double(session.count))
                .padding(.top)
            Text("\(index + 1) of \(session.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            FlashcardCardView(
                prompt: prompt,
                frontIsPronunciation: mode == .pronunciation,
                answerTerm: answerTerm,
                termReading: termReading,
                partsOfSpeech: posLabels,
                answerFacts: answerFacts,
                notes: word.notes,
                isFlipped: isFlipped
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isFlipped.toggle()
                }
            }

            // In pronunciation mode the audio button is the prompt (shown on
            // the front); otherwise it's part of the revealed answer. Falls back
            // to a synthesized voice when the word has no recording.
            if showAudioButton(mode), let key = pronunciationKey(for: word) {
                Button {
                    activatePronunciation(for: word)
                } label: {
                    Label(playback.playingPath == key ? "Stop" : "Play pronunciation",
                          systemImage: playback.playingPath == key ? "stop.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
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

    // MARK: - Helpers

    /// The phonetic reading shown on the term side: pinyin for Chinese,
    /// hiragana for Japanese (only when recorded).
    private func reading(for word: VocabWord) -> String? {
        let value: String?
        switch learningLanguage {
        case "zh": value = word.pinyin
        case "ja": value = word.hiragana
        default: value = word.reading
        }
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Session logic

    /// Whether a card should be included for a given mode: the mode must apply to
    /// the word (pronunciation needs a recording), and — when reviewing due cards
    /// only — that aspect must not have been remembered yet today.
    private func includes(_ card: PracticeCard, mode: FrontMode) -> Bool {
        // Pronunciation practice needs something to hear: a recording, or a
        // synthesized voice when the list has text-to-speech enabled.
        if mode == .pronunciation && card.word.audioPath == nil && !ttsEnabled { return false }
        if dueOnly {
            // Daily assignment: each mode follows its own spaced-repetition schedule.
            switch mode {
            case .translation:
                return card.word.isTranslationDue()
            case .term:
                return card.word.isWordDue()
            case .pronunciation:
                return card.word.isPronunciationDue()
            }
        } else {
            // Free practice: show every word except finally-remembered ones.
            return card.word.remember_final != true
        }
    }

    private func deck() -> [SessionItem] {
        guard !selectedModes.isEmpty else { return [] }
        // One card per selected aspect a word still needs today, so a word can
        // appear once per aspect (e.g. both its translation and pronunciation).
        var items: [SessionItem] = []
        for mode in selectedModes {
            for card in cards where includes(card, mode: mode) {
                let promptIndex: Int?
                switch mode {
                case .term: promptIndex = 0
                case .translation: promptIndex = card.word.factValues.indices.randomElement() ?? 0
                case .pronunciation: promptIndex = nil
                }
                items.append(SessionItem(card: card, mode: mode, promptIndex: promptIndex))
            }
        }
        return weightedReviewOrder(items) { item in
            item.card.word.reviewWeight(for: item.mode.memoryAspect)
        }
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
        // Progress (remembered counts/dates) is only recorded for the daily
        // assignment; otherwise it's free practice that doesn't affect stats.
        if dueOnly {
            if correct {
                item.card.word.markCorrect(aspect: item.mode.memoryAspect, ttsEnabled: ttsEnabled)
                recordDailyStat(aspect: item.mode.memoryAspect)
            } else {
                item.card.word.markIncorrect(aspect: item.mode.memoryAspect)
            }
            session[index] = item
            // A word can be queued for multiple aspects; keep all of its copies
            // in sync so one aspect's save doesn't clobber another's stats.
            syncWord(item.card.word)
            persist(item.card)
        }
        if correct {
            correctCount += 1
        } else {
            // Not remembered: move on, but re-queue it (same mode) for review.
            session.append(item)
        }
        advance()
    }

    /// Propagates a word's updated state to every queued item for the same word.
    private func syncWord(_ word: VocabWord) {
        for i in session.indices where session[i].card.word.id == word.id {
            session[i].card.word = word
        }
    }

    private func persist(_ card: PracticeCard) {
        guard let uid = auth.uid else { return }
        Task { try? await VocabRepository.updateWord(uid: uid, listId: card.listId, word: card.word, ttsEnabled: ttsEnabled) }
    }

    private func recordDailyStat(aspect: String) {
        guard let uid = auth.uid else { return }
        Task { try? await VocabRepository.recordRemembered(uid: uid, aspect: aspect) }
    }

    private func advance() {
        withAnimation { isFlipped = false }
        if index + 1 < session.count {
            index += 1
        } else {
            isFinished = true
        }
    }

    private func endSession() {
        isFinished = true
    }

    private func resetToSetup() {
        session = []
        index = 0
        correctCount = 0
        isFlipped = false
        isFinished = false
    }
}
