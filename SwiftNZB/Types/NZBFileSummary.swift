//
//  NZBFileSummary.swift
//  SwiftNZB
//

import Foundation

/// One `<file>` within an NZB: a logical file reconstructed from its ordered segments.
struct NZBFileSummary: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// The raw `subject` attribute from the NZB (often contains the filename in quotes).
    var subject: String
    /// Filename parsed out of `subject` (best effort), used for on-disk naming and display.
    var filename: String
    /// Newsgroups the segments were posted to.
    var groups: [String]
    var segments: [NZBSegmentSummary]
    /// Sum of segment `byteCount`s — the declared total size of this file.
    var totalBytes: Int
    /// Bytes successfully downloaded + decoded so far (updated from engine progress).
    var downloadedBytes: Int

    var progress: Double {
        totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : 0
    }

    /// True for the PAR2 recovery files (`.par2`) — used to drive verification UI.
    var isPar2: Bool { filename.lowercased().hasSuffix(".par2") }

    init(
        id: UUID = UUID(),
        subject: String,
        filename: String,
        groups: [String],
        segments: [NZBSegmentSummary],
        downloadedBytes: Int = 0
    ) {
        self.id = id
        self.subject = subject
        self.filename = filename
        self.groups = groups
        self.segments = segments
        self.totalBytes = segments.reduce(0) { $0 + $1.byteCount }
        self.downloadedBytes = downloadedBytes
    }

    // Migration-safe decoder.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
        segments = try c.decodeIfPresent([NZBSegmentSummary].self, forKey: .segments) ?? []
        totalBytes = try c.decodeIfPresent(Int.self, forKey: .totalBytes)
            ?? segments.reduce(0) { $0 + $1.byteCount }
        downloadedBytes = try c.decodeIfPresent(Int.self, forKey: .downloadedBytes) ?? 0
    }
}
