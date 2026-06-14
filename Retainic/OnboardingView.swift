//
//  OnboardingView.swift
//  Retainic
//
//  Two-step first-run flow: pick native language, then the language to learn.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""
    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""

    @State private var step = 0
    @State private var selectedNative: String = ""
    @State private var selectedTarget: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 2)
                    .padding()

                TabView(selection: $step) {
                    languageStep(
                        title: "What's your native language?",
                        subtitle: "We'll show translations in this language.",
                        selection: $selectedNative,
                        exclude: nil
                    )
                    .tag(0)

                    languageStep(
                        title: "What do you want to learn?",
                        subtitle: "You'll add and practice words in this language.",
                        selection: $selectedTarget,
                        exclude: selectedNative
                    )
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                footerButton
            }
            .navigationTitle("Welcome to Retainic")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func languageStep(title: String, subtitle: String, selection: Binding<String>, exclude: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(Language.all.filter { $0.code != exclude }) { language in
                Button {
                    selection.wrappedValue = language.code
                } label: {
                    HStack {
                        Text(language.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.wrappedValue == language.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var footerButton: some View {
        let canContinue = step == 0 ? !selectedNative.isEmpty : !selectedTarget.isEmpty
        Button {
            if step == 0 {
                withAnimation { step = 1 }
            } else {
                nativeLanguage = selectedNative
                targetLanguage = selectedTarget
            }
        } label: {
            Text(step == 0 ? "Continue" : "Start Learning")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canContinue)
        .padding()
    }
}

#Preview {
    OnboardingView()
}
