//
//  ServerUsageStore.swift
//  SwiftNZB
//
//  Records how much each server has downloaded, so a per-server stats card can show rolling
//  24h / 7d / 30d / all-time volume. Recent per-completion records (≤90 days) drive the rolling
//  windows; a cumulative per-server counter survives pruning for the all-time total.
//

import Foundation
import Observation

struct ServerUsageRecord: Codable, Sendable {
    let serverID: UUID
    let date: Date
    let bytes: Int
}

@MainActor
@Observable
final class ServerUsageStore {
    static let shared = ServerUsageStore()

    private(set) var records: [ServerUsageRecord] = []
    private var allTime: [UUID: Int] = [:]

    private let recordsKey = "serverUsage.records.v1"
    private let allTimeKey = "serverUsage.allTime.v1"
    private let defaults = UserDefaults.standard
    private let retentionDays = 90

    private init() { load() }

    struct Stats: Sendable {
        var day: Int
        var week: Int
        var month: Int
        var allTime: Int
    }

    func record(serverID: UUID, bytes: Int, at date: Date = Date()) {
        guard bytes > 0 else { return }
        records.append(ServerUsageRecord(serverID: serverID, date: date, bytes: bytes))
        allTime[serverID, default: 0] += bytes
        prune(now: date)
        persist()
    }

    func stats(for serverID: UUID, now: Date = Date()) -> Stats {
        func sum(daysAgo days: Double) -> Int {
            let cutoff = now.addingTimeInterval(-days * 86_400)
            return records.lazy
                .filter { $0.serverID == serverID && $0.date >= cutoff }
                .reduce(0) { $0 + $1.bytes }
        }
        return Stats(day: sum(daysAgo: 1), week: sum(daysAgo: 7), month: sum(daysAgo: 30),
                     allTime: allTime[serverID] ?? 0)
    }

    func remove(serverID: UUID) {
        records.removeAll { $0.serverID == serverID }
        allTime[serverID] = nil
        persist()
    }

    // MARK: - Persistence

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        records.removeAll { $0.date < cutoff }
    }

    private func load() {
        if let data = defaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([ServerUsageRecord].self, from: data) {
            records = decoded
        }
        if let data = defaults.data(forKey: allTimeKey),
           let decoded = try? JSONDecoder().decode([UUID: Int].self, from: data) {
            allTime = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: recordsKey) }
        if let data = try? JSONEncoder().encode(allTime) { defaults.set(data, forKey: allTimeKey) }
    }
}
