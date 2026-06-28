//
//  audio.js
//  Retainic Web
//
//  Pronunciation recording (MediaRecorder) and playback (HTMLAudioElement keyed
//  by Storage path). Web counterpart of AudioManager.swift.
//

import { audioURL } from "./repository.js";

/** MediaRecorder options tuned for speech: an efficient codec (Opus when
 *  available) at a low bitrate, so recordings are small before upload. */
function recorderOptions() {
  const opts = { audioBitsPerSecond: 24000 };
  const types = ["audio/webm;codecs=opus", "audio/ogg;codecs=opus", "audio/mp4", "audio/webm"];
  if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported) {
    const m = types.find((t) => MediaRecorder.isTypeSupported(t));
    if (m) opts.mimeType = m;
  }
  return opts;
}

// MARK: - Shared playback store (play a recording by its Storage path)

class AudioPlaybackStore {
  constructor() {
    this.playingPath = null;
    this.audio = null;
    this.listeners = new Set();
    this.urlCache = new Map();
  }
  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  _notify() { this.listeners.forEach((fn) => fn(this.playingPath)); }

  async toggle(path) {
    if (this.playingPath === path) { this.stop(); return; }
    this.stop();
    try {
      let url = this.urlCache.get(path);
      if (!url) { url = await audioURL(path); this.urlCache.set(path, url); }
      this.audio = new Audio(url);
      this.audio.onended = () => { this.playingPath = null; this._notify(); };
      this.playingPath = path;
      this._notify();
      await this.audio.play();
    } catch (e) {
      this.playingPath = null;
      this._notify();
    }
  }

  stop() {
    if (this.audio) { this.audio.pause(); this.audio = null; }
    if (this.playingPath) { this.playingPath = null; this._notify(); }
  }
}

export const playback = new AudioPlaybackStore();

// MARK: - Recorder (used by the add/edit word form)

export class PronunciationRecorder {
  constructor() {
    this.isRecording = false;
    this.isPlaying = false;
    this.permissionDenied = false;
    this.recordingWasEmpty = false;
    this.recordedBlob = null;       // freshly recorded clip to upload
    this.hasExistingAudio = false;  // an already-saved recording on the word
    this._existingURL = null;
    this._previewURL = null;
    this._mediaRecorder = null;
    this._chunks = [];
    this._stream = null;
    this._previewAudio = null;
    this.onChange = () => {};
  }

  get hasAudio() { return this.recordedBlob != null || this.hasExistingAudio; }

  async configure(existingAudioPath) {
    if (existingAudioPath) {
      this.hasExistingAudio = true;
      try { this._existingURL = await audioURL(existingAudioPath); } catch {}
      this.onChange();
    }
  }

  async toggleRecording() {
    if (this.isRecording) { this._stopRecording(); return; }
    this.recordingWasEmpty = false;
    try {
      // Mono + voice processing keeps pronunciation clips small.
      this._stream = await navigator.mediaDevices.getUserMedia({
        audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
      });
    } catch (e) {
      this.permissionDenied = true;
      this.onChange();
      return;
    }
    this._chunks = [];
    this._mediaRecorder = new MediaRecorder(this._stream, recorderOptions());
    this._mediaRecorder.ondataavailable = (e) => { if (e.data.size) this._chunks.push(e.data); };
    this._mediaRecorder.onstop = () => {
      const blob = new Blob(this._chunks, { type: this._mediaRecorder.mimeType || "audio/webm" });
      if (blob.size === 0) {
        this.recordingWasEmpty = true;
      } else {
        this.recordedBlob = blob;
        this.hasExistingAudio = false;
        if (this._previewURL) URL.revokeObjectURL(this._previewURL);
        this._previewURL = URL.createObjectURL(blob);
      }
      this._stream?.getTracks().forEach((t) => t.stop());
      this._stream = null;
      this.isRecording = false;
      this.onChange();
    };
    this._mediaRecorder.start();
    this.isRecording = true;
    this.onChange();
  }

  _stopRecording() { this._mediaRecorder?.stop(); }

  play() {
    const url = this._previewURL || this._existingURL;
    if (!url) return;
    this.stopPlayback();
    this._previewAudio = new Audio(url);
    this._previewAudio.onended = () => { this.isPlaying = false; this.onChange(); };
    this._previewAudio.play();
    this.isPlaying = true;
    this.onChange();
  }

  stopPlayback() {
    if (this._previewAudio) { this._previewAudio.pause(); this._previewAudio = null; }
    if (this.isPlaying) { this.isPlaying = false; this.onChange(); }
  }

  clear() {
    this.stopPlayback();
    this.recordedBlob = null;
    this.hasExistingAudio = false;
    if (this._previewURL) { URL.revokeObjectURL(this._previewURL); this._previewURL = null; }
    this._existingURL = null;
    this.onChange();
  }
}
