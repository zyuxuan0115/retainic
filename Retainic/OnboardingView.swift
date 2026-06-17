//
//  OnboardingView.swift
//  Retainic
//
//  First-run flow: pick your native language. The language you're learning is
//  chosen per-list when you create a list.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

    @State private var selectedNative: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's your native language?")
                    .font(.title2.bold())
                Text("We'll show translations and grammar labels in this language.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                List(Language.all) { language in
                    Button {
                        selectedNative = language.code
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedNative == language.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Button {
                    nativeLanguage = selectedNative
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedNative.isEmpty)
                .padding(.top)
            }
            .padding()
            .navigationTitle("Welcome to Retainic")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    OnboardingView()
}
