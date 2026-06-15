//
//  ServerAccount.swift
//  SwiftNZB
//

import Foundation

/// A configured Usenet (NNTP) server. Non-secret metadata is synced via iCloud KVS
/// (see `ServerStore`); the password is stored separately in the synchronizable Keychain,
/// keyed by `id` — it is intentionally NOT part of this struct.
struct ServerAccount: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Display label, e.g. "Eweka", "Newshosting".
    var name: String
    var host: String
    var port: Int
    var useSSL: Bool
    var username: String
    /// Provider's allowed simultaneous connections — the engine's per-server worker count.
    var maxConnections: Int
    /// Lower = preferred when filling segments across servers (multi-server, later phase).
    var priority: Int
    /// Whether this account participates in downloads.
    var isEnabled: Bool

    /// Conventional default port for the current SSL setting.
    static func defaultPort(useSSL: Bool) -> Int { useSSL ? 563 : 119 }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 563,
        useSSL: Bool = true,
        username: String = "",
        maxConnections: Int = 20,
        priority: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.username = username
        self.maxConnections = maxConnections
        self.priority = priority
        self.isEnabled = isEnabled
    }

    // Migration-safe decoder: new fields default so older synced payloads still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        useSSL = try c.decodeIfPresent(Bool.self, forKey: .useSSL) ?? true
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? Self.defaultPort(useSSL: useSSL)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        maxConnections = try c.decodeIfPresent(Int.self, forKey: .maxConnections) ?? 20
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}
