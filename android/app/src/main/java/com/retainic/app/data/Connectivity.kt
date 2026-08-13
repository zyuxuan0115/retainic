package com.retainic.app.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Whether the device currently has a validated network. The repositories read
 * this to decide between waiting on Firestore and going straight to its
 * on-disk cache; the UI reads it to say so. Ported alongside Connectivity.swift.
 */
object Connectivity {
    /** For Compose. Non-UI code should read [isOnlineNow], which is thread-safe. */
    var isOnline by mutableStateOf(true)
        private set

    private val current = AtomicBoolean(true)
    private val main = Handler(Looper.getMainLooper())

    val isOnlineNow: Boolean get() = current.get()

    /** Starts watching the default network. Called once, from Application. */
    fun start(context: Context) {
        val manager = context.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return

        // Seed from the network in place at launch, so the first read doesn't
        // wait on a request that can't succeed before any callback arrives.
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
        update(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)

        try {
            manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = update(true)
                override fun onLost(network: Network) = update(false)
                override fun onUnavailable() = update(false)
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                    update(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
            })
        } catch (_: Exception) {
            // Without the callback we stay on the launch-time reading rather
            // than blocking every write on a wait we can't judge.
        }
    }

    private fun update(online: Boolean) {
        current.set(online)
        main.post { if (isOnline != online) isOnline = online }
    }
}
