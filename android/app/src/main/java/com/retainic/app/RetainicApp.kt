package com.retainic.app

import android.app.Application
import com.retainic.app.audio.AudioPlaybackStore
import com.retainic.app.data.AudioCache
import com.retainic.app.data.Connectivity
import com.retainic.app.data.FirestoreOffline

/**
 * Application entry point. Firebase auto-initializes via the google-services
 * plugin; here we wire up the shared audio/TTS playback store and everything
 * the app needs to work with no connection.
 */
class RetainicApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Before anything reads or writes: the cache settings only take effect
        // while Firestore is untouched, and the repositories consult the
        // network state on their very first call.
        FirestoreOffline.configure()
        Connectivity.start(this)
        AudioCache.init(this)
        AudioPlaybackStore.init(this)
    }
}
