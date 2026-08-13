package com.retainic.app.data

import android.content.Context
import java.io.File
import java.security.MessageDigest

/**
 * Pronunciation clips kept on disk, keyed by their Storage path. A port of
 * AudioCache.swift.
 *
 * Firestore's cache covers the words themselves but not their recordings, which
 * live in Firebase Storage — so without this a cached list would show every word
 * offline and be unable to play any of them. A clip is written here the first
 * time it is fetched (and as soon as it is recorded), which is what makes
 * practising a list you have already been through work with no connection.
 */
object AudioCache {
    /** Roughly a few thousand clips at the ~4 KB/s these recordings encode to. */
    private const val MAX_BYTES = 200L * 1024 * 1024

    private val lock = Any()
    private var directory: File? = null

    /**
     * filesDir rather than cacheDir: the point of the cache is to still be
     * there when the network isn't, and the system empties cacheDir under
     * storage pressure.
     */
    fun init(context: Context) {
        directory = File(context.applicationContext.filesDir, "pronunciation_audio")
            .apply { mkdirs() }
    }

    /** Storage paths contain slashes, so they're hashed into a flat filename. */
    private fun fileFor(path: String): File? {
        val dir = directory ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(path.toByteArray())
        return File(dir, digest.joinToString("") { "%02x".format(it) } + ".m4a")
    }

    /**
     * The cached clip for [path], or null. Touches the file's timestamp so the
     * least recently *used* clip is the one trimming drops.
     */
    fun cached(path: String): ByteArray? = synchronized(lock) {
        val file = fileFor(path) ?: return null
        if (!file.exists()) return null
        return try {
            file.readBytes().also { file.setLastModified(System.currentTimeMillis()) }
        } catch (e: Exception) {
            null
        }
    }

    fun store(data: ByteArray, path: String) {
        synchronized(lock) {
            val file = fileFor(path) ?: return
            try {
                file.writeBytes(data)
            } catch (e: Exception) {
                return
            }
        }
        trim()
    }

    /**
     * Copies a just-recorded clip in, so it plays back offline straight away
     * rather than after a round trip it may not be able to make.
     */
    fun store(file: File, path: String) {
        val data = try { file.readBytes() } catch (e: Exception) { return }
        store(data, path)
    }

    fun remove(path: String) {
        synchronized(lock) { fileFor(path)?.delete() }
    }

    /** Drops the oldest clips once the cache outgrows its cap. */
    private fun trim() {
        synchronized(lock) {
            val files = directory?.listFiles()?.toList() ?: return
            var total = files.sumOf { it.length() }
            if (total <= MAX_BYTES) return
            for (file in files.sortedBy { it.lastModified() }) {
                val size = file.length()
                if (file.delete()) total -= size
                if (total <= MAX_BYTES) break
            }
        }
    }
}
