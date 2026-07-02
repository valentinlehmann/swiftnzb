//
//  NetworkPathObserver.swift
//  SwiftNZB
//
//  Watches connectivity so the DownloadManager can park downloads when the network drops or
//  when the user has opted out of cellular, rebuild connections when the interface changes
//  (Wi-Fi↔cellular handoff), and resume when a usable path returns. Rapid flaps are debounced.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkPathObserver {
    static let shared = NetworkPathObserver()

    struct Status: Equatable {
        var isOnline: Bool
        var isExpensive: Bool
        var isConstrained: Bool
        /// Coarse interface identity; a change means an interface handoff (rebuild sockets).
        var interface: String
    }

    private(set) var isOnline = true
    private(set) var isExpensive = false
    private(set) var isConstrained = false

    /// Called on the main actor whenever connectivity changes (after debouncing). `interfaceChanged`
    /// is true when the underlying interface switched while still online — the signal to tear down
    /// and re-establish connections bound to the old path.
    var onChange: (@MainActor (_ isOnline: Bool, _ isExpensive: Bool, _ isConstrained: Bool, _ interfaceChanged: Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "de.valentinlehmann.swiftnzb.netpath")
    private var last: Status?
    private var debounceTask: Task<Void, Never>?
    private static let debounce: Duration = .milliseconds(800)

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = Status(
                isOnline: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                interface: nwInterfaceLabel(path))
            Task { @MainActor in self?.schedule(status) }
        }
        monitor.start(queue: queue)
    }

    /// Coalesce rapid path flaps: a momentary blip shouldn't trigger a full engine teardown +
    /// reconnect storm. We debounce, then deliver only genuine changes.
    private func schedule(_ status: Status) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.apply(status)
        }
    }

    private func apply(_ status: Status) {
        let previous = last
        last = status
        isOnline = status.isOnline
        isExpensive = status.isExpensive
        isConstrained = status.isConstrained

        guard status != previous else { return }
        // An interface switch while online (e.g. Wi-Fi → cellular) leaves existing sockets bound to
        // a dead path; flag it so the manager rebuilds them instead of stalling on timeouts.
        let interfaceChanged = status.isOnline && (previous?.isOnline ?? false)
            && status.interface != (previous?.interface ?? status.interface)
        onChange?(status.isOnline, status.isExpensive, status.isConstrained, interfaceChanged)
    }
}

/// Coarse interface identity, computed off the monitor's background queue (nonisolated).
private func nwInterfaceLabel(_ path: NWPath) -> String {
    if path.usesInterfaceType(.wiredEthernet) { return "ethernet" }
    if path.usesInterfaceType(.wifi) { return "wifi" }
    if path.usesInterfaceType(.cellular) { return "cellular" }
    if path.usesInterfaceType(.loopback) { return "loopback" }
    return "other"
}
