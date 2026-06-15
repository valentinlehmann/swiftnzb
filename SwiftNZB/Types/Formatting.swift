//
//  Formatting.swift
//  SwiftNZB
//
//  Display helpers that return plain Strings for `Text(verbatim:)` — avoids the locale
//  thousands-separator that `Text("\(int)")` would insert into byte counts / speeds / counts.
//

import Foundation

enum Format {
    /// e.g. "1.2 GB". Uses the binary/file convention Usenet users expect.
    static func bytes(_ count: Int) -> String {
        Int64(max(0, count)).formatted(.byteCount(style: .file))
    }

    /// e.g. "4.5 MB/s".
    static func speed(_ bytesPerSecond: Int) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    /// e.g. "42%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// Coarse human ETA from a remaining byte count and current rate. nil if rate is ~0.
    static func eta(remainingBytes: Int, bytesPerSecond: Int) -> String? {
        guard bytesPerSecond > 0, remainingBytes > 0 else { return nil }
        let seconds = Double(remainingBytes) / Double(bytesPerSecond)
        return duration(seconds)
    }

    /// e.g. "3m 20s", "1h 4m", "12s".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// Deadline date from now for a remaining byte count and rate — feeds the Live Activity's
    /// self-updating `Text(timerInterval:)`. nil if rate is ~0.
    static func etaDeadline(remainingBytes: Int, bytesPerSecond: Int, from now: Date = Date()) -> Date? {
        guard bytesPerSecond > 0, remainingBytes > 0 else { return nil }
        return now.addingTimeInterval(Double(remainingBytes) / Double(bytesPerSecond))
    }
}
