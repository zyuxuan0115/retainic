//
//  AudioManager.swift
//  Retainic
//
//  Records a pronunciation clip (AVAudioRecorder) and plays back local or
//  Firebase Storage audio (AVAudioPlayer).
//

import Foundation
import Combine
import AVFoundation

// MARK: - Recorder (used while adding/editing a word)

@MainActor
final class PronunciationRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var permissionDenied = false
    /// Set when the last recording captured no audio (e.g. on the Simulator).
    @Published var recordingWasEmpty = false
    /// Set when a brand-new clip has been recorded this session.
    @Published private(set) var recordedURL: URL?

    /// Storage path of an already-saved recording (when editing a word).
    @Published var existingAudioPath: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    /// Whether there is any audio to play / save (new or previously saved).
    var hasAudio: Bool { recordedURL != nil || existingAudioPath != nil }
    /// Whether the user recorded a new clip that needs uploading.
    var hasNewRecording: Bool { recordedURL != nil }

    func configure(existingAudioPath: String?) {
        self.existingAudioPath = existingAudioPath
    }

    // MARK: Recording

    func toggleRecording() {
        isRecording ? stopRecording() : requestAndStartRecording()
    }

    private func requestAndStartRecording() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.beginRecording()
                } else {
                    self.permissionDenied = true
                }
            }
        }
    }

    private func beginRecording() {
        stopPlayback()
        recordingWasEmpty = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("retainic-rec-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            let started = recorder.record()
            guard started else {
                print("⚠️ AVAudioRecorder.record() returned false")
                isRecording = false
                return
            }
            self.recorder = recorder
            self.recordedURL = url
            isRecording = true
        } catch {
            print("⚠️ recording error: \(error)")
            isRecording = false
        }
    }

    private func stopRecording() {
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        // Keep the session active; playback reconfigures the category itself.

        if let url = recordedURL {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
            print("🎙️ recorded \(String(format: "%.1f", duration))s, \(size) bytes")
            // A valid AAC clip is well over 1 KB; treat tiny files as empty so we
            // never upload audio that can't be played back.
            if size < 1_000 {
                print("⚠️ recording is empty — microphone captured no audio (common on the Simulator).")
                try? FileManager.default.removeItem(at: url)
                recordedURL = nil
                recordingWasEmpty = true
            }
        }
    }

    /// Discards the current recording (new clip or reference to a saved one).
    func clear() {
        stopPlayback()
        stopRecording()
        if let url = recordedURL { try? FileManager.default.removeItem(at: url) }
        recordedURL = nil
        existingAudioPath = nil
    }

    // MARK: Playback

    func play() {
        if let url = recordedURL {
            play(localURL: url)
        } else if let path = existingAudioPath {
            Task { await playRemote(path: path) }
        }
    }

    private func playRemote(path: String) async {
        do {
            let data = try await VocabRepository.downloadAudioData(path: path)
            play(data: data)
        } catch {
            isPlaying = false
        }
    }

    private func play(localURL: URL) {
        do {
            try activatePlaybackSession()
            let player = try AVAudioPlayer(contentsOf: localURL)
            start(player)
        } catch {
            print("⚠️ local playback error: \(error)")
            isPlaying = false
        }
    }

    private func play(data: Data) {
        do {
            try activatePlaybackSession()
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue)
            start(player)
        } catch {
            print("⚠️ data playback error: \(error)")
            isPlaying = false
        }
    }

    private func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func start(_ player: AVAudioPlayer) {
        player.delegate = self
        player.volume = 1
        player.prepareToPlay()
        let ok = player.play()
        self.player = player
        isPlaying = ok
        if !ok { print("⚠️ AVAudioPlayer.play() returned false") }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}

extension PronunciationRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

// MARK: - Playback-only store (used in lists / flashcards)

/// Shared player for tapping a word's pronunciation outside the editor.
@MainActor
final class AudioPlaybackStore: NSObject, ObservableObject {
    static let shared = AudioPlaybackStore()

    /// Storage path currently playing, for highlighting the active button.
    @Published private(set) var playingPath: String?

    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]

    func toggle(path: String) {
        if playingPath == path {
            stop()
        } else {
            Task { await play(path: path) }
        }
    }

    private func play(path: String) async {
        stop()
        do {
            let data: Data
            if let cached = cache[path] {
                data = cached
            } else {
                data = try await VocabRepository.downloadAudioData(path: path)
                cache[path] = data
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue)
            player.delegate = self
            player.volume = 1
            player.prepareToPlay()
            if player.play() {
                self.player = player
                playingPath = path
            } else {
                print("⚠️ AudioPlaybackStore.play() returned false")
                playingPath = nil
            }
        } catch {
            print("⚠️ remote playback error: \(error)")
            playingPath = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingPath = nil
    }
}

extension AudioPlaybackStore: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingPath = nil }
    }
}
