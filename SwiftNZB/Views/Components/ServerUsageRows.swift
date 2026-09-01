//
//  ServerUsageRows.swift
//  SwiftNZB
//
//  How much one server has downloaded, as plain list rows (24h / 7d / 30d / all time).
//

import SwiftUI

struct ServerUsageRows: View {
    let serverID: UUID
    @State private var store = ServerUsageStore.shared

    var body: some View {
        let stats = store.stats(for: serverID)
        // A Group, not a stack: the rows have to reach the enclosing List as four separate rows.
        Group {
            if stats.allTime == 0 {
                // Four zeroes say less than one sentence does.
                Text("Nothing downloaded from this server yet.")
                    .foregroundStyle(.secondary)
            } else {
                row("Last 24 Hours", stats.day)
                row("Last 7 Days", stats.week)
                row("Last 30 Days", stats.month)
                row("All Time", stats.allTime)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ bytes: Int) -> some View {
        StatRow(title, Format.bytes(bytes))
    }
}
