//
//  QueueView.swift
//  SwiftNZB
//

import SwiftUI
import UniformTypeIdentifiers

struct QueueView: View {
    @State private var manager = DownloadManager.shared
    @State private var isImporting = false
    @State private var cancelCandidate: DownloadJob?

    private var nzbTypes: [UTType] {
        [UTType("de.valentinlehmann.swiftnzb.nzb"), UTType(filenameExtension: "nzb"), .xml]
            .compactMap { $0 }
    }

    private var activeJobs: [DownloadJob] {
        manager.queueJobs.filter { $0.status.isActive || $0.id == manager.activeJobID }
    }
    private var waitingJobs: [DownloadJob] { manager.waitingQueueJobs }

    var body: some View {
        // NOTE: a real container (ZStack) — not a Group — so the presentation
        // modifiers below are hosted on one stable view. With a Group, modifiers
        // attach to each child individually, so the .fileImporter would be torn
        // down when the empty↔list content swaps mid-presentation, leaving
        // `isImporting` stuck `true` and the dialog permanently unopenable.
        ZStack {
            if manager.queueJobs.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Queue")
        .navigationDestination(for: UUID.self) { JobDetailView(jobID: $0) }
        .toolbar { toolbar }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: nzbTypes, allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                ImportCoordinator.shared.handle(url: url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "nzb" }) ?? urls.first else { return false }
            ImportCoordinator.shared.handle(url: url)
            return true
        }
        .confirmationDialog("Cancel this download?", isPresented: cancelBinding, titleVisibility: .visible) {
            Button("Cancel Download", role: .destructive) {
                if let id = cancelCandidate?.id { manager.cancel(id) }
                cancelCandidate = nil
            }
            Button("Keep Downloading", role: .cancel) { cancelCandidate = nil }
        } message: {
            Text("The partially downloaded files will be deleted.")
        }
    }

    private var cancelBinding: Binding<Bool> {
        Binding(get: { cancelCandidate != nil }, set: { if !$0 { cancelCandidate = nil } })
    }

    /// Single entry point for both the empty-state and toolbar "Add NZB" buttons.
    /// Guards against re-triggering while the picker is already presenting so
    /// rapid taps can't desync the presentation state.
    private func presentImporter() {
        guard !isImporting else { return }
        isImporting = true
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Downloads", systemImage: "tray.and.arrow.down")
        } description: {
            Text("Import an NZB file to start downloading.")
        } actions: {
            Button("Add NZB") { presentImporter() }
                .buttonStyle(.glassProminent)
        }
    }

    private var list: some View {
        List {
            if let active = manager.activeJob {
                Section {
                    summaryHeader(active)
                        .listRowBackground(Color.clear)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            if !activeJobs.isEmpty {
                Section("Active") { ForEach(activeJobs) { jobRow($0) } }
            }
            if !waitingJobs.isEmpty {
                Section("Queued") {
                    ForEach(waitingJobs) { jobRow($0) }
                        .onMove { manager.moveQueued(fromOffsets: $0, toOffset: $1) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if manager.isWaitingForNetwork {
                Label("Waiting for network…", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: manager.isWaitingForNetwork)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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
        if waitingJobs.count > 1 {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { presentImporter() } label: { Label("Add NZB", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
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
                    Text(manager.isWaitingForNetwork ? "Waiting for network…" : job.status.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.default, value: job.progress)
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(Format.percent(job.progress))
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
            Button(role: .destructive) { cancelCandidate = job } label: {
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
