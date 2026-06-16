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

    private var activeJobs: [DownloadJob] {
        manager.queueJobs.filter { $0.status.isActive || $0.id == manager.activeJobID }
    }
    private var waitingJobs: [DownloadJob] {
        manager.queueJobs.filter { !($0.status.isActive || $0.id == manager.activeJobID) }
    }

    var body: some View {
        List {
            if manager.queueJobs.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "tray.and.arrow.down")
                    } description: {
                        Text("Import an NZB file to start downloading.")
                    } actions: {
                        Button("Add NZB") { isImporting = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                if let active = manager.activeJob {
                    Section { summaryHeader(active) }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                if !activeJobs.isEmpty {
                    Section("Active") { ForEach(activeJobs) { jobRow($0) } }
                }
                if !waitingJobs.isEmpty {
                    Section("Queued") { ForEach(waitingJobs) { jobRow($0) } }
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

    @ViewBuilder
    private func summaryHeader(_ job: DownloadJob) -> some View {
        let remaining = max(0, job.totalBytes - job.downloadedBytes)
        let downloading = job.status == .downloading
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                progressRing(job)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.name).font(.headline).lineLimit(1)
                    Text(verbatim: manager.isWaitingForNetwork ? "Waiting for network…" : job.status.titleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                StatTile("Speed", downloading ? Format.speed(manager.aggregateBytesPerSecond) : "—",
                         systemImage: "speedometer", tint: downloading ? .accentColor : .secondary)
                StatTile("Remaining", Format.bytes(remaining), systemImage: "arrow.down.circle")
            }
            HStack(spacing: 10) {
                StatTile("ETA",
                         downloading ? (Format.eta(remainingBytes: remaining, bytesPerSecond: manager.aggregateBytesPerSecond) ?? "—") : "—",
                         systemImage: "clock")
                StatTile("Connections", "\(manager.activeConnections)", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .padding(.vertical, 4)
    }

    private func progressRing(_ job: DownloadJob) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: job.progress)
                .stroke(job.status.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: job.progress)
            Text(verbatim: Format.percent(job.progress))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(width: 58, height: 58)
    }

    @ViewBuilder
    private func jobRow(_ job: DownloadJob) -> some View {
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
