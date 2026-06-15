//
//  HistoryView.swift
//  SwiftNZB
//

import SwiftUI

struct HistoryView: View {
    @State private var manager = DownloadManager.shared

    var body: some View {
        List {
            if manager.historyJobs.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No History",
                        systemImage: "checkmark.circle",
                        message: "Completed and cancelled downloads appear here."
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(manager.historyJobs) { job in
                    NavigationLink(value: job.id) {
                        HStack {
                            Image(systemName: job.status.systemImage)
                                .foregroundStyle(job.status.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.name).lineLimit(1)
                                Text(verbatim: "\(Format.bytes(job.totalBytes)) · \(job.status.titleText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { manager.removeFromHistory(job.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: UUID.self) { JobDetailView(jobID: $0) }
        .toolbar {
            if !manager.historyJobs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { manager.clearHistory() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
    }
}
