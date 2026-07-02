//
//  ServerStore.swift
//  SwiftNZB
//
//  CRUD + persistence for Usenet server accounts. Non-secret metadata syncs via iCloud
//  Key-Value Store (mirrored to UserDefaults, degrading to local-only if iCloud KVS isn't
//  available); passwords live in the synchronizable Keychain keyed by account id.
//

import Foundation
import Observation

@MainActor
@Observable
final class ServerStore {
    static let shared = ServerStore()

    private(set) var accounts: [ServerAccount] = []

    private let key = "servers.v1"
    private let defaults = UserDefaults.standard
    private let kvs = NSUbiquitousKeyValueStore.default

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
        kvs.synchronize()
    }

    var hasServers: Bool { !accounts.isEmpty }

    func account(_ id: UUID) -> ServerAccount? { accounts.first { $0.id == id } }

    /// The default server for new downloads: lowest priority value among enabled accounts.
    var primaryServer: ServerAccount? {
        accounts.filter(\.isEnabled).min { $0.priority < $1.priority } ?? accounts.first
    }

    func password(for id: UUID) -> String? { Keychain.password(for: id.uuidString) }

    func upsert(_ account: ServerAccount, password: String?) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        if let password { Keychain.setPassword(password, for: account.id.uuidString) }
        persist()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        Keychain.deletePassword(for: id.uuidString)
        ServerUsageStore.shared.remove(serverID: id)   // don't leave orphaned usage records behind
        if SettingsStore.shared.settings.defaultServerID == id {
            SettingsStore.shared.settings.defaultServerID = nil
        }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        let data = (kvs.data(forKey: key)) ?? defaults.data(forKey: key)
        guard let data, let decoded = try? JSONDecoder().decode([ServerAccount].self, from: data) else {
            accounts = []
            return
        }
        accounts = decoded.sorted { $0.priority < $1.priority }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: key)
        kvs.set(data, forKey: key)
        kvs.synchronize()
    }
}
