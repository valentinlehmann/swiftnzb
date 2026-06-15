//
//  NetworkPathObserver.swift
//  SwiftNZB
//
//  Watches connectivity so the DownloadManager can park downloads when the network drops or
//  when the user has opted out of cellular, and resume when a usable path returns.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkPathObserver {
    static let shared = NetworkPathObserver()

    private(set) var isOnline = true
    private(set) var isExpensive = false

    /// Called on the main actor whenever connectivity changes.
    var onChange: (@MainActor (_ isOnline: Bool, _ isExpensive: Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "de.valentinlehmann.swiftnzb.netpath")

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                let changed = online != self.isOnline || expensive != self.isExpensive
                self.isOnline = online
                self.isExpensive = expensive
                if changed { self.onChange?(online, expensive) }
            }
        }
        monitor.start(queue: queue)
    }
}
