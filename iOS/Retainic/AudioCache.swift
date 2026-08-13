//
//  AudioCache.swift
//  Retainic
//
//  Pronunciation clips kept on disk, keyed by their Storage path.
//
//  Firestore's cache covers the words themselves but not their recordings,
//  which live in Firebase Storage — so without this a cached list would show
//  every word offline and be unable to play any of them. A clip is written here
//  the first time it is fetched (and as soon as it is recorded), which is what
//  makes practising a list you have already been through work with no
//  connection.
//

import CryptoKit
import Foundation

enum AudioCache {
    /// Roughly a few thousand clips at the ~4 KB/s these recordings encode to.
    private static let maxBytes = 200 * 1024 * 1024

    private static let lock = NSLock()

    /// Application Support rather than Caches: the point of the cache is to
    /// still be there when the network isn't, and the system may empty Caches
    /// whenever it likes. Excluded from backup — every clip is re-downloadable.
    private static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        var url = base.appendingPathComponent("PronunciationAudio", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            print("⚠️ audio cache directory error: \(error)")
        }
        return url
    }()

    /// Storage paths are long and contain slashes, so they're hashed into a
    /// flat filename.
    private static func fileURL(for path: String) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".m4a")
    }

    /// The cached clip for `path`, or nil. Touches the file's modification date
    /// so the least recently *used* clip is the one trimming drops.
    static func cached(_ path: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL(for: path),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    static func store(_ data: Data, for path: String) {
        lock.lock()
        guard let url = fileURL(for: path) else { lock.unlock(); return }
        try? data.write(to: url, options: .atomic)
        lock.unlock()
        trim()
    }

    /// Copies a just-recorded clip in, so it plays back offline straight away
    /// rather than after a round trip it may not be able to make.
    static func store(contentsOf fileURL: URL, for path: String) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        store(data, for: path)
    }

    static func remove(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL(for: path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Drops the oldest clips once the cache outgrows its cap.
    private static func trim() {
        lock.lock()
        defer { lock.unlock() }
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
              ) else { return }

        let files: [(url: URL, date: Date, size: Int)] = names.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, size)
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }

        for file in files.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
            if total <= maxBytes { break }
        }
    }
}
