//
//  NZBSegmentSummary.swift
//  SwiftNZB
//

import Foundation

/// A single Usenet article segment referenced by an NZB `<segment>` element. UI-light: the
/// download engine owns retry/server state; this is just enough to render and to feed the engine.
struct NZBSegmentSummary: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// The Usenet message-id (without surrounding angle brackets).
    var messageID: String
    /// Declared decoded size of this segment, in bytes (the NZB `bytes` attribute).
    var byteCount: Int
    /// 1-based part number (the NZB `number` attribute), used to order segments within a file.
    var number: Int

    init(id: UUID = UUID(), messageID: String, byteCount: Int, number: Int) {
        self.id = id
        self.messageID = messageID
        self.byteCount = byteCount
        self.number = number
    }

    // Migration-safe decoder: tolerate older/partial payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        messageID = try c.decodeIfPresent(String.self, forKey: .messageID) ?? ""
        byteCount = try c.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
    }
}
