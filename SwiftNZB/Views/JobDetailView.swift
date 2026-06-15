//
//  JobDetailView.swift
//  SwiftNZB
//

import SwiftUI

struct JobDetailView: View {
    let jobID: UUID
    @State private var manager = DownloadManager.shared
    @State private var showingFiles = false

    private var job: DownloadJob? { manager.jobs.first { $0.id == jobID } }

    var body: some View {
        if let job {
            List {
                Section { header(job) }
                Section { controls(job) }
                    .listRowBackground(Color.clear)
                if let error = job.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle").font(.callout) }
                }
                Section("Files") {
                    ForEach(job.files) { FileProgressRow(file: $0) }
                }
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingFiles) {
                NavigationStack { FileBrowserView(job: job) }
            }
        } else {
            ContentUnavailableView("Download Removed", systemImage: "tray")
        }
    }

    @ViewBuilder
    private func header(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusChip(status: job.status)
                Spacer()
                if job.status == .downloading, manager.activeJobID == job.id {
                    Text(verbatim: Format.speed(manager.aggregateBytesPerSecond))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: job.progress) { Text(verbatim: Format.percent(job.progress)) }
                .tint(job.status.tint)
            HStack {
                Text(verbatim: "\(Format.bytes(job.downloadedBytes)) / \(Format.bytes(job.totalBytes))")
                Spacer()
                if job.status == .downloading, manager.activeJobID == job.id, manager.activeConnections > 0 {
                    Text(verbatim: "\(manager.activeConnections) connections")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func controls(_ job: DownloadJob) -> some View {
        HStack(spacing: 24) {
            Spacer()
            switch job.status {
            case .downloading, .queued:
                CircleActionButton(systemImage: "pause.fill", tint: .orange) { manager.pause(job.id) }
            case .paused, .failed:
                CircleActionButton(systemImage: "play.fill", tint: .green) { manager.resume(job.id) }
            case .completed:
                CircleActionButton(systemImage: "folder", tint: .accentColor) { showingFiles = true }
            default:
                EmptyView()
            }
            if !job.status.isTerminal {
                CircleActionButton(systemImage: "xmark", tint: .red, role: .destructive) { manager.cancel(job.id) }
            }
            Spacer()
        }
    }
}
