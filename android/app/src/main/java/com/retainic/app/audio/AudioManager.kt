package com.retainic.app.audio

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.retainic.app.data.VocabRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/**
 * Records a pronunciation clip (MediaRecorder) and plays back local or Firebase
 * Storage audio (MediaPlayer). Ported from AudioManager.swift.
 */
class PronunciationRecorder(private val context: Context) {
    var isRecording by mutableStateOf(false)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var permissionDenied by mutableStateOf(false)
    /** Set when the last recording captured no audio. */
    var recordingWasEmpty by mutableStateOf(false)
        private set

    /** A brand-new clip recorded this session. */
    var recordedFile: File? by mutableStateOf(null)
        private set
    /** Storage path of an already-saved recording (when editing a word). */
    var existingAudioPath: String? by mutableStateOf(null)

    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null

    /** Whether there is any audio to play / save (new or previously saved). */
    val hasAudio: Boolean get() = recordedFile != null || existingAudioPath != null
    val hasNewRecording: Boolean get() = recordedFile != null

    fun configure(existingAudioPath: String?) {
        this.existingAudioPath = existingAudioPath
    }

    // MARK: Recording

    fun startRecording() {
        stopPlayback()
        recordingWasEmpty = false
        try {
            val file = File.createTempFile("retainic-rec-", ".m4a", context.cacheDir)
            @Suppress("DEPRECATION")
            val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else MediaRecorder()
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioChannels(1)
            rec.setAudioSamplingRate(22_050)
            rec.setAudioEncodingBitRate(32_000)
            rec.setOutputFile(file.absolutePath)
            rec.prepare()
            rec.start()
            recorder = rec
            recordedFile = file
            isRecording = true
        } catch (e: Exception) {
            isRecording = false
        }
    }

    fun stopRecording() {
        try {
            recorder?.stop()
        } catch (_: Exception) {
        }
        recorder?.release()
        recorder = null
        isRecording = false

        val file = recordedFile
        // A valid AAC clip is well over 1 KB; treat tiny files as empty.
        if (file != null && file.length() < 1_000) {
            file.delete()
            recordedFile = null
            recordingWasEmpty = true
        }
    }

    /** Discards the current recording (new clip or reference to a saved one). */
    fun clear() {
        stopPlayback()
        if (isRecording) stopRecording()
        recordedFile?.delete()
        recordedFile = null
        existingAudioPath = null
    }

    // MARK: Playback

    fun play(scope: CoroutineScope) {
        val local = recordedFile
        val path = existingAudioPath
        when {
            local != null -> playLocal(local)
            path != null -> scope.launch { playRemote(path) }
        }
    }

    private fun playLocal(file: File) {
        try {
            val mp = MediaPlayer()
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener { isPlaying = false }
            mp.prepare()
            mp.start()
            player = mp
            isPlaying = true
        } catch (e: Exception) {
            isPlaying = false
        }
    }

    private suspend fun playRemote(path: String) {
        try {
            val data = VocabRepository.downloadAudioData(path)
            val tmp = withContext(Dispatchers.IO) {
                File.createTempFile("retainic-play-", ".m4a", context.cacheDir).apply { writeBytes(data) }
            }
            playLocal(tmp)
        } catch (e: Exception) {
            isPlaying = false
        }
    }

    fun stopPlayback() {
        player?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        player = null
        isPlaying = false
    }
}

/**
 * Shared player for tapping a word's pronunciation outside the editor. Plays a
 * recorded clip (by Storage path) or a synthesized voice (TTS). Ported from
 * AudioPlaybackStore in AudioManager.swift.
 */
object AudioPlaybackStore {
    /** Storage path or "tts:"-prefixed key currently playing (for button state). */
    var playingPath: String? by mutableStateOf(null)
        private set

    private lateinit var appContext: Context
    private var player: MediaPlayer? = null
    private val cache = HashMap<String, ByteArray>()
    private val scope = CoroutineScope(Dispatchers.Main)

    private var tts: TextToSpeech? = null
    private var ttsReady = false

    fun init(context: Context) {
        appContext = context.applicationContext
        tts = TextToSpeech(appContext) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
        }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    scope.launch { if (playingPath?.startsWith("tts:") == true) playingPath = null }
                }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    scope.launch { if (playingPath?.startsWith("tts:") == true) playingPath = null }
                }
            })
        }
    }

    fun ttsKey(text: String): String = "tts:$text"

    fun toggle(path: String) {
        if (playingPath == path) stop() else scope.launch { play(path) }
    }

    /** Speaks [text] in [language], or stops if that utterance is already playing. */
    fun toggleSpeak(text: String, language: String) {
        val key = ttsKey(text)
        if (playingPath == key) {
            stop()
            return
        }
        stop()
        val engine = tts ?: return
        engine.language = Locale.forLanguageTag(bcp47(language))
        val slowdown = mapOf("en" to 0.95f, "ja" to 0.6f, "zh" to 0.75f)
        engine.setSpeechRate(slowdown[language] ?: 1.0f)
        playingPath = key
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, key)
    }

    private fun bcp47(language: String): String = when (language) {
        "en" -> "en-US"
        "es" -> "es-ES"
        "zh" -> "zh-CN"
        "ja" -> "ja-JP"
        "ko" -> "ko-KR"
        else -> language
    }

    private suspend fun play(path: String) {
        stop()
        try {
            val data = cache[path] ?: withContext(Dispatchers.IO) {
                VocabRepository.downloadAudioData(path)
            }.also { cache[path] = it }
            val tmp = withContext(Dispatchers.IO) {
                File.createTempFile("retainic-store-", ".m4a", appContext.cacheDir).apply { writeBytes(data) }
            }
            val mp = MediaPlayer()
            mp.setDataSource(tmp.absolutePath)
            mp.setOnCompletionListener { playingPath = null }
            mp.prepare()
            mp.start()
            player = mp
            playingPath = path
        } catch (e: Exception) {
            playingPath = null
        }
    }

    fun stop() {
        player?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        player = null
        tts?.let { if (it.isSpeaking) it.stop() }
        playingPath = null
    }
}
