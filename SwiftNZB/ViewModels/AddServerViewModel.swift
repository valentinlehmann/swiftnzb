//
//  AddServerViewModel.swift
//  SwiftNZB
//

import Foundation
import Observation
import DownloadEngine

@MainActor
@Observable
final class AddServerViewModel {
    enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    var name: String
    // Connection-relevant fields reset the test result so a green check always reflects the
    // values currently on screen (and a fresh test is required again after an edit).
    var host: String { didSet { invalidateTest() } }
    var portText: String { didSet { invalidateTest() } }
    var useSSL: Bool {
        didSet {
            if portWasDefault(oldUseSSL: oldValue) { portText = String(ServerAccount.defaultPort(useSSL: useSSL)) }
            invalidateTest()
        }
    }
    var username: String { didSet { invalidateTest() } }
    var password: String { didSet { invalidateTest() } }
    var maxConnectionsText: String
    var testState: TestState = .idle

    private let editingID: UUID?

    private func invalidateTest() { if testState != .idle { testState = .idle } }

    init(existing: ServerAccount? = nil) {
        if let s = existing {
            editingID = s.id
            name = s.name
            host = s.host
            portText = String(s.port)
            useSSL = s.useSSL
            username = s.username
            // Loaded lazily via loadPassword() — a synchronous (iCloud) Keychain read in init
            // made every server row in the list expensive to build, which felt like swipe lag.
            password = ""
            maxConnectionsText = String(s.maxConnections)
        } else {
            editingID = nil
            name = ""
            host = ""
            useSSL = true
            portText = String(ServerAccount.defaultPort(useSSL: true))
            username = ""
            password = ""
            maxConnectionsText = "20"
        }
    }

    var isEditing: Bool { editingID != nil }
    var editingServerID: UUID? { editingID }
    var port: Int { Int(portText) ?? ServerAccount.defaultPort(useSSL: useSSL) }
    var maxConnections: Int { max(1, Int(maxConnectionsText) ?? 20) }
    var hasValidPort: Bool {
        guard let p = Int(portText) else { return false }
        return (1...65535).contains(p)
    }

    var canSave: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && hasValidPort }

    /// Save the server, testing the connection first for a new one (an existing server isn't
    /// forced to re-test). Returns true if it was saved, so the caller can dismiss.
    func commit() async -> Bool {
        guard canSave else { return false }
        if !isEditing && testState != .success {
            await test()
            guard testState == .success else { return false }
        }
        save()
        return true
    }

    private func portWasDefault(oldUseSSL: Bool) -> Bool {
        Int(portText) == ServerAccount.defaultPort(useSSL: oldUseSSL)
    }

    func makeAccount() -> ServerAccount {
        ServerAccount(
            id: editingID ?? UUID(),
            name: name.isEmpty ? host : name,
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            useSSL: useSSL,
            username: username.trimmingCharacters(in: .whitespaces),
            maxConnections: maxConnections
        )
    }

    /// Load the existing password from the Keychain (called when the editor appears, off the
    /// list-rendering path).
    func loadPassword() {
        guard let id = editingID, password.isEmpty else { return }
        if let stored = ServerStore.shared.password(for: id) {
            password = stored
            testState = .idle   // setting password triggers invalidateTest; keep it idle
        }
    }

    func save() {
        ServerStore.shared.upsert(makeAccount(), password: password.isEmpty ? nil : password)
    }

    func test() async {
        testState = .testing
        let account = makeAccount()
        let config = ServerConfig(
            host: account.host, port: account.port, useSSL: account.useSSL,
            username: account.username.isEmpty ? nil : account.username,
            password: password.isEmpty ? nil : password,
            maxConnections: 1
        )
        if let failure = await ServerProbe.test(config) {
            testState = .failure(failure)
        } else {
            testState = .success
        }
    }
}
