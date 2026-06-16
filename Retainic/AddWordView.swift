//
//  AddWordView.swift
//  Retainic
//
//  Create a new word in a list, or edit an existing one. Backed by Firestore.
//

import SwiftUI

struct AddWordView: View {
    let listId: String
    /// Existing word when editing; nil when creating.
    private let existingWord: VocabWord?

    @AppStorage(AppStorageKey.targetLanguage) private var targetLanguage = ""
    @AppStorage(AppStorageKey.nativeLanguage) private var nativeLanguage = ""

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var term: String
    @State private var translation: String
    @State private var notes: String
    @State private var selectedPOS: Set<PartOfSpeech>
    @State private var hiragana: String
    @State private var pinyin: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @StateObject private var recorder = PronunciationRecorder()

    init(listId: String, word: VocabWord? = nil) {
        self.listId = listId
        self.existingWord = word
        _term = State(initialValue: word?.term ?? "")
        _translation = State(initialValue: word?.translation ?? "")
        _notes = State(initialValue: word?.notes ?? "")
        _selectedPOS = State(initialValue: Set(word?.partOfSpeechValues ?? []))
        _hiragana = State(initialValue: word?.hiragana ?? "")
        _pinyin = State(initialValue: word?.pinyin ?? "")
    }

    private var isEditing: Bool { existingWord != nil }

    /// Hiragana is only relevant when the target language is Japanese.
    private var isLearningJapanese: Bool { targetLanguage == "ja" }
    /// Pinyin is shown — and required — when the target language is Chinese.
    private var isLearningChinese: Bool { targetLanguage == "zh" }

    private var canSave: Bool {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty,
              !translation.trimmingCharacters(in: .whitespaces).isEmpty,
              !isSaving else { return false }
        // Pinyin is mandatory for Chinese.
        if isLearningChinese && pinyin.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    var body: some View {
        Form {
            Section(Language.named(targetLanguage)?.displayName ?? "Word") {
                TextField("Word you're learning", text: $term)
                    .textInputAutocapitalization(.never)
            }

            if isLearningJapanese {
                Section("Hiragana (optional)") {
                    TextField("ひらがな reading", text: $hiragana)
                        .textInputAutocapitalization(.never)
                }
            }

            if isLearningChinese {
                Section {
                    TextField("pīnyīn reading", text: $pinyin)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Pinyin (required)")
                } footer: {
                    if pinyin.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Pinyin is required for Chinese words.")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section(Language.named(nativeLanguage)?.displayName ?? "Translation") {
                TextField("Translation", text: $translation)
            }

            Section {
                ForEach(PartOfSpeech.allCases.filter { $0 != .unspecified }) { pos in
                    Button {
                        toggle(pos)
                    } label: {
                        HStack {
                            Text(pos.label(for: nativeLanguage))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedPOS.contains(pos) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("Part of speech")
            } footer: {
                Text("Select all that apply.")
            }

            pronunciationSection

            Section("Notes (optional)") {
                TextField("Example sentence or memory hint", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle(isEditing ? "Edit Word" : "New Word")
        .navigationBarTitleDisplayMode(.inline)
        .task { recorder.configure(existingAudioPath: existingWord?.audioPath) }
        .onDisappear { recorder.stopPlayback() }
        .toolbar {
            if !isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    @ViewBuilder
    private var pronunciationSection: some View {
        Section {
            Button {
                recorder.toggleRecording()
            } label: {
                Label(
                    recorder.isRecording ? "Stop Recording" : (recorder.hasAudio ? "Re-record" : "Record"),
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill"
                )
                .foregroundStyle(recorder.isRecording ? .red : .accentColor)
            }

            if recorder.hasAudio && !recorder.isRecording {
                Button {
                    recorder.isPlaying ? recorder.stopPlayback() : recorder.play()
                } label: {
                    Label(recorder.isPlaying ? "Stop" : "Play", systemImage: recorder.isPlaying ? "stop.fill" : "play.fill")
                }
                Button(role: .destructive) {
                    recorder.clear()
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
            }
        } header: {
            Text("Pronunciation (optional)")
        } footer: {
            if recorder.permissionDenied {
                Text("Microphone access is off. Enable it in Settings to record.")
                    .foregroundStyle(.red)
            }
        }
    }

    private func toggle(_ pos: PartOfSpeech) {
        if selectedPOS.contains(pos) {
            selectedPOS.remove(pos)
        } else {
            selectedPOS.insert(pos)
        }
    }

    private func save() {
        guard let uid = auth.uid else { return }
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let trimmedHiragana = hiragana.trimmingCharacters(in: .whitespaces)
        let hiraganaValue = trimmedHiragana.isEmpty ? nil : trimmedHiragana
        let trimmedPinyin = pinyin.trimmingCharacters(in: .whitespaces)
        let pinyinValue = trimmedPinyin.isEmpty ? nil : trimmedPinyin
        // Keep a stable order matching the enum's declaration order.
        let posList = PartOfSpeech.allCases.filter { selectedPOS.contains($0) }

        // Audio: a freshly recorded clip to upload, or removal of an existing one.
        let newAudioURL = recorder.recordedURL
        let removeAudio = isEditing && existingWord?.audioPath != nil && !recorder.hasAudio

        isSaving = true
        errorMessage = nil

        Task {
            do {
                if var word = existingWord {
                    word.term = trimmedTerm
                    word.translation = trimmedTranslation
                    word.notes = trimmedNotes
                    word.partsOfSpeech = posList.map(\.rawValue)
                    word.partOfSpeech = nil
                    word.hiragana = hiraganaValue
                    word.pinyin = pinyinValue
                    try await VocabRepository.updateWord(
                        uid: uid, listId: listId, word: word,
                        newAudioFileURL: newAudioURL, removeAudio: removeAudio
                    )
                } else {
                    let word = VocabWord(
                        term: trimmedTerm,
                        translation: trimmedTranslation,
                        notes: trimmedNotes,
                        partsOfSpeech: posList,
                        hiragana: hiraganaValue,
                        pinyin: pinyinValue
                    )
                    try await VocabRepository.addWord(uid: uid, listId: listId, word: word, audioFileURL: newAudioURL)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
