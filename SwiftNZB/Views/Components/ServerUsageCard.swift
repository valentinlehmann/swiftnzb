//
//  ServerUsageCard.swift
//  SwiftNZB
//
//  A 2×2 grid of download-volume stats for one server (24h / 7d / 30d / all time).
//

import SwiftUI

struct ServerUsageCard: View {
    let serverID: UUID
    @State private var store = ServerUsageStore.shared

    var body: some View {
        let stats = store.stats(for: serverID)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile("Last 24h", Format.bytes(stats.day), systemImage: "clock")
                StatTile("Last 7 days", Format.bytes(stats.week), systemImage: "calendar")
            }
            HStack(spacing: 10) {
                StatTile("Last 30 days", Format.bytes(stats.month), systemImage: "calendar")
                StatTile("All time", Format.bytes(stats.allTime), systemImage: "sum")
            }
        }
    }
}
