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
}

struct FlashcardView: View {
    let cards: [PracticeCard]
    /// Language of the words being studied (the `term` side), from the list.
    /// Determines whether the reading is pinyin (Chinese) or hiragana (Japanese).
    let learningLanguage: String

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
                     : "No cards due right now — but you can review everything.")
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
                    if selectedModes.contains(.pronunciation) {
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
        // The front is a bare prompt (term or translation, per the card's mode);
        // the answer side always reveals the full entry: the word being learned,
        // its reading, parts of speech, the meaning, and the pronunciation button.
        let termReading = reading(for: word)
        let posLabels = word.partOfSpeechValues.map { $0.label(for: preferredLanguage) }
        return VStack(spacing: 24) {
            ProgressView(value: Double(index), total: Double(session.count))
                .padding(.top)
            Text("\(index + 1) of \(session.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            CardView(
                prompt: mode == .translation ? word.translation : word.term,
                frontIsPronunciation: mode == .pronunciation,
                term: word.term,
                termReading: termReading,
                partsOfSpeech: posLabels,
                translation: word.translation,
                notes: word.notes,
                isFlipped: isFlipped
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isFlipped.toggle()
                }
            }

            // In pronunciation mode the audio button is the prompt (shown on
            // the front); otherwise it's part of the revealed answer.
            if showAudioButton(mode), let path = word.audioPath {
                Button {
                    playback.toggle(path: path)
                } label: {
                    Label(playback.playingPath == path ? "Stop" : "Play pronunciation",
                          systemImage: playback.playingPath == path ? "stop.fill" : "speaker.wave.2.fill")
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
        if mode == .pronunciation && card.word.audioPath == nil { return false }
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
                items.append(SessionItem(card: card, mode: mode))
            }
        }
        // Prioritise lower Leitner boxes, then shuffle within the selection.
        return items.shuffled().sorted { $0.card.word.box < $1.card.word.box }
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
                item.card.word.markCorrect(aspect: item.mode.memoryAspect)
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
        Task { try? await VocabRepository.updateWord(uid: uid, listId: card.listId, word: card.word) }
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

// MARK: - Card

private struct CardView: View {
    /// What's shown before flipping (the question): term or translation.
    let prompt: String
    /// When true the front shows a "listen" prompt instead of `prompt` text.
    var frontIsPronunciation: Bool = false
    /// The word being learned, always revealed on the answer side.
    let term: String
    var termReading: String?
    var partsOfSpeech: [String] = []
    /// The meaning, revealed on the answer side.
    let translation: String
    let notes: String
    let isFlipped: Bool

    private var reading: String? {
        guard let termReading, !termReading.isEmpty else { return nil }
        return termReading
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(isFlipped ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)

            if isFlipped {
                answerSide
            } else if frontIsPronunciation {
                VStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text("Listen and recall")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
            } else {
                Text(prompt)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(32)
            }
        }
        .frame(height: 280)
        .overlay(alignment: .top) {
            Text(isFlipped ? "Answer" : "Tap to flip")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var answerSide: some View {
        VStack(spacing: 10) {
            Text(term)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)

            if let reading {
                Text(reading)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if !partsOfSpeech.isEmpty {
                HStack(spacing: 6) {
                    ForEach(partsOfSpeech, id: \.self) { pos in
                        Text(pos)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }

            Divider().padding(.horizontal, 32)

            Text(translation)
                .font(.title3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)

            if !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}
