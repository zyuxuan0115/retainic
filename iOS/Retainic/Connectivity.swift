//
//  Connectivity.swift
//  Retainic
//
//  Whether the device currently has a network path, and the banner that tells
//  the user when it doesn't. The repositories read this to decide between
//  waiting on Firestore and going straight to its on-disk cache.
//

import Combine
import Network
import SwiftUI

final class Connectivity: ObservableObject, @unchecked Sendable {
    static let shared = Connectivity()

    /// For SwiftUI. Non-UI code should read `isOnlineNow`, which is safe to
    /// touch from any thread.
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.retainic.connectivity")
    private let lock = NSLock()
    private var current = true

    /// Thread-safe snapshot of the same value `isOnline` publishes.
    var isOnlineNow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    private init() {}

    /// Starts watching the network path. Called once, at launch.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            self.lock.lock()
            self.current = online
            self.lock.unlock()
            DispatchQueue.main.async {
                if self.isOnline != online { self.isOnline = online }
            }
        }
        monitor.start(queue: queue)
    }
}

/// A slim bar shown above a screen's content while the device is offline, so
/// the lists and terms on show are understood as the saved copy rather than
/// mistaken for everything the account holds.
struct OfflineBanner: View {
    @ObservedObject private var connectivity = Connectivity.shared
    let language: String

    var body: some View {
        if !connectivity.isOnline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                Text("Offline — showing your saved copy.".localized(language))
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.15))
        }
    }
}
