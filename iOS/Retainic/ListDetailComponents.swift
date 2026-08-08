//
//  ListDetailComponents.swift
//  Retainic
//
//  Reusable rows and sheets presented by ListDetailView.
//

import SwiftUI
import UIKit

struct WordRow: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @ObservedObject private var playback = AudioPlaybackStore.shared
    let word: VocabWord
    let learningLanguage: String
    /// Whether the list falls back to a synthesized voice for words with no
    /// recording.
    let ttsEnabled: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(word.term)
                        .font(.headline)
                    if let reading = word.reading {
                        Text(reading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(word.partOfSpeechValues) { pos in
                        Text(pos.label(for: preferredLanguage))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                Text(word.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let key = pronunciationKey {
                Spacer()
                Button {
                    activatePronunciation()
                } label: {
                    Image(systemName: playback.playingPath == key ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    /// The active-playback key for this word's pronunciation: its recording path,
    /// or a TTS key when the list falls back to a synthesized voice — nil when the
    /// word has neither.
    private var pronunciationKey: String? {
        if let path = word.audioPath { return path }
        if ttsEnabled { return AudioPlaybackStore.ttsKey(word.term) }
        return nil
    }

    private func activatePronunciation() {
        if let path = word.audioPath {
            playback.toggle(path: path)
        } else if ttsEnabled {
            playback.toggleSpeak(text: word.term, language: learningLanguage)
        }
    }
}

/// Per-list settings: rename the list and reset every word's remembered state.
struct ListSettingsSheet: View {
    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @Binding private var filter: WordFilter
    /// The text-to-speech switch is pending until Save: flipping it changes
    /// nothing until the checkmark applies it, and closing the sheet discards it.
    @State private var ttsOn: Bool
    @State private var showingResetConfirm = false
    @State private var showingShareConfirm = false
    private let originalName: String
    private let originalTTS: Bool
    let publicId: String?
    let onSave: (String) -> Void
    let onSetTTS: (Bool) -> Void
    let onResetMemory: () -> Void

    init(name: String, filter: Binding<WordFilter>, ttsEnabled: Bool, publicId: String?, onSave: @escaping (String) -> Void, onSetTTS: @escaping (Bool) -> Void, onResetMemory: @escaping () -> Void) {
        _name = State(initialValue: name)
        _filter = filter
        _ttsOn = State(initialValue: ttsEnabled)
        self.originalName = name
        self.originalTTS = ttsEnabled
        self.publicId = publicId
        self.onSave = onSave
        self.onSetTTS = onSetTTS
        self.onResetMemory = onResetMemory
    }

    /// Save needs a usable name and something to apply: a new name, a flipped
    /// text-to-speech switch, or both.
    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed != originalName.trimmingCharacters(in: .whitespaces) || ttsOn != originalTTS
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("List name") {
                    TextField("List name", text: $name)
                }

                Section("Show words") {
                    Picker("Show words", selection: $filter) {
                        ForEach(WordFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                }

                Section {
                    Toggle("Text-to-speech", isOn: $ttsOn)
                } footer: {
                    Text("Read words aloud with a synthesized voice when they have no recording.")
                }

                Section {
                    Button {
                        shareUniqueId()
                    } label: {
                        Label("Share List", systemImage: "square.and.arrow.up")
                    }
                    .disabled((publicId ?? "").isEmpty)
                } footer: {
                    Text("Copies this list's unique ID so others can recreate it.")
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Mark all as not remembered", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Every word in this list will show up again in practice for all methods.")
                }
            }
            .navigationTitle("List Settings".localized(preferredLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .alert("Unique ID copied".localized(preferredLanguage), isPresented: $showingShareConfirm) {
                Button("OK".localized(preferredLanguage), role: .cancel) {}
            } message: {
                Text("Share it with others so they can create the exact same wordlist.")
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("List Settings".localized(preferredLanguage)).font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if ttsOn != originalTTS { onSetTTS(ttsOn) }
                        if name.trimmingCharacters(in: .whitespaces)
                            != originalName.trimmingCharacters(in: .whitespaces) { onSave(name) }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("Save"))
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Mark all words as not remembered?".localized(preferredLanguage),
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark All as Not Remembered".localized(preferredLanguage), role: .destructive) {
                    onResetMemory()
                    dismiss()
                }
                Button("Cancel".localized(preferredLanguage), role: .cancel) {}
            }
        }
    }

    /// Copies the list's unique ID to the clipboard so it can be shared.
    private func shareUniqueId() {
        guard let id = publicId, !id.isEmpty else { return }
        UIPasteboard.general.string = id
        showingShareConfirm = true
    }
}

/// Picks a destination list for moving the selected words. Only lists with a
/// matching learning + original language are offered.
struct MoveDestinationSheet: View {
    let targets: [VocabularyList]
    let count: Int
    let onSelect: (VocabularyList) -> Void

    @AppStorage(AppStorageKey.preferredLanguage) private var preferredLanguage = Language.systemDefault
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if targets.isEmpty {
                    ContentUnavailableView {
                        Label("No Compatible Lists", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("You need another list with the same learning and native language to move these words.")
                    }
                } else {
                    List(targets) { list in
                        Button {
                            onSelect(list)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.stack.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(list.wordCount) words")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move %lld Words".localized(preferredLanguage, count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Move %lld Words".localized(preferredLanguage, count)).font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
            }
        }
    }
}
