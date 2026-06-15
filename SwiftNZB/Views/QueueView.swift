//
//  QueueView.swift
//  SwiftNZB
//

import SwiftUI
import UniformTypeIdentifiers

struct QueueView: View {
    @State private var manager = DownloadManager.shared
    @State private var isImporting = false

    private var nzbTypes: [UTType] {
        [UTType("de.valentinlehmann.swiftnzb.nzb"), UTType(filenameExtension: "nzb"), .xml]
            .compactMap { $0 }
    }

    var body: some View {
        List {
            if manager.queueJobs.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No Downloads",
                        systemImage: "tray",
                        message: "Tap + to import an NZB file."
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(manager.queueJobs) { job in
                    NavigationLink(value: job.id) {
                        JobRowView(
                            job: job,
                            bytesPerSecond: job.id == manager.activeJobID ? manager.aggregateBytesPerSecond : 0
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { manager.cancel(job.id) } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        if job.status == .paused || job.status == .failed {
                            Button { manager.resume(job.id) } label: { Label("Resume", systemImage: "play.fill") }
                                .tint(.green)
                        } else if job.status == .downloading || job.status == .queued {
                            Button { manager.pause(job.id) } label: { Label("Pause", systemImage: "pause.fill") }
                                .tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("Queue")
        .navigationDestination(for: UUID.self) { JobDetailView(jobID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !manager.queueJobs.isEmpty {
                    Button {
                        if manager.isQueuePaused { manager.resumeAll() } else { manager.pauseAll() }
                    } label: {
                        Label(
                            manager.isQueuePaused ? "Resume All" : "Pause All",
                            systemImage: manager.isQueuePaused ? "play.fill" : "pause.fill"
                        )
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isImporting = true } label: { Label("Add NZB", systemImage: "plus") }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: nzbTypes, allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                ImportCoordinator.shared.handle(url: url)
            }
        }
        .overlay(alignment: .bottom) {
            if manager.isWaitingForNetwork {
                Label("Waiting for network…", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}
