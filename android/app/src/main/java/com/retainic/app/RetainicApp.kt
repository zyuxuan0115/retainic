package com.retainic.app

import android.app.Application
import com.retainic.app.audio.AudioPlaybackStore

/**
 * Application entry point. Firebase auto-initializes via the google-services
 * plugin; here we wire up the shared audio/TTS playback store.
 */
class RetainicApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AudioPlaybackStore.init(this)
    }
}
