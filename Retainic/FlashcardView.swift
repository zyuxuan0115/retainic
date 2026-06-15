//
//  FlashcardView.swift
//  Retainic
//
//  Flip-card practice for one list, driven by the Leitner boxes.
//  Review results are persisted back to Firestore.
//

import SwiftUI

struct FlashcardView: View {
    let listName: String
    let listId: String
    let words: [VocabWord]

    @EnvironmentObject private var auth: AuthService

    @State private var session: [VocabWord] = []
    @State private var index = 0
    @State private var isFlipped = false
    @State private var showFrontIsTerm = true
    @State private var correctCount = 0
    @State private var isFinished = false
    @State private var dueOnly = true

    var body: some View {
        Group {
            if words.isEmpty {
                emptyState
            } else if session.isEmpty {
                setupView
            } else if isFinished {
                summaryView
            } else {
                practiceView
            }
        }
        .navigationTitle("Practice")
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
            description: Text("Add some words to this list first, then come back to review them.")
        )
    }

    private var dueCount: Int { words.filter(\.isDue).count }

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
                     ? "\(dueCount) card\(dueCount == 1 ? "" : "s") due in “\(listName)”."
                     : "No cards due right now — but you can review everything.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                Toggle("Review due cards only", isOn: $dueOnly)
                Toggle("Show translation first", isOn: Binding(
                    get: { !showFrontIsTerm },
                    set: { showFrontIsTerm = !$0 }
                ))
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
        let card = session[index]
        return VStack(spacing: 24) {
            ProgressView(value: Double(index), total: Double(session.count))
                .padding(.top)
            Text("\(index + 1) of \(session.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            CardView(
                front: showFrontIsTerm ? card.term : card.translation,
                back: showFrontIsTerm ? card.translation : card.term,
                notes: card.notes,
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
            Text("You got \(correctCount) of \(session.count) right.")
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

    private func deck() -> [VocabWord] {
        let pool = dueOnly ? words.filter(\.isDue) : words
        // Prioritise lower Leitner boxes, then shuffle within the selection.
        return pool.shuffled().sorted { $0.box < $1.box }
    }

    private func startSession() {
        let cards = deck()
        guard !cards.isEmpty else { return }
        session = cards
        index = 0
        correctCount = 0
        isFlipped = false
        isFinished = false
    }

    private func handleAnswer(correct: Bool) {
        var card = session[index]
        if correct {
            card.markCorrect()
            correctCount += 1
        } else {
            card.markIncorrect()
        }
        session[index] = card
        persist(card)
        advance()
    }

    private func persist(_ card: VocabWord) {
        guard let uid = auth.uid else { return }
        Task { try? await VocabRepository.updateWord(uid: uid, listId: listId, word: card) }
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
    let front: String
    let back: String
    let notes: String
    let isFlipped: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(isFlipped ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)

            VStack(spacing: 12) {
                Text(isFlipped ? back : front)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)

                if isFlipped && !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .frame(height: 280)
        .overlay(alignment: .top) {
            Text(isFlipped ? "Answer" : "Tap to flip")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}
