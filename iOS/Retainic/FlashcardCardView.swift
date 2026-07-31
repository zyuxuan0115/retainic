//
//  FlashcardCardView.swift
//  Retainic
//
//  The flip-card visual, extracted so FlashcardView stays focused on session
//  state and below the repository's module-size cap.
//

import SwiftUI

struct FlashcardCardView: View {
    let prompt: String
    var frontIsPronunciation = false
    /// Nil when the term itself was the prompt and must not be repeated.
    let answerTerm: String?
    var termReading: String?
    var partsOfSpeech: [String] = []
    let answerFacts: [String]
    let notes: String
    let isFlipped: Bool

    private var reading: String? {
        guard answerTerm != nil, let termReading, !termReading.isEmpty else { return nil }
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
        .frame(height: 300)
        .overlay(alignment: .top) {
            Text(isFlipped ? "Answer" : "Tap to flip")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var answerSide: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let answerTerm {
                    Text(answerTerm)
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
                }

                if answerTerm != nil && !answerFacts.isEmpty {
                    Divider().padding(.horizontal, 32)
                }

                ForEach(Array(answerFacts.enumerated()), id: \.offset) { _, fact in
                    Text(fact)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }

                if !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}
