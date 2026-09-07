//
//  QueueView.swift
//  SwiftNZB
//

import SwiftUI
import UniformTypeIdentifiers

struct QueueView: View {
    @State private var manager = DownloadManager.shared
    @State private var router = AppRouter.shared
    @State private var isImporting = false
    @State private var cancelCandidate: DownloadJob?
    @State private var entitlements = Entitlements.shared
    @State private var showingPaywall = false

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
        .overlay(alignment: .bottom) { bottomBanner }
        .animation(.default, value: manager.recentlyCompletedJobID)
        .animation(.default, value: entitlements.freeDownloadsRemaining)
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(isModal: true) }
                .presentationSizing(.form)
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
            Text("SwiftNZB deletes the partly downloaded files.")
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
            if isOutOfFreeDownloads {
                Text("You have used your 10 free downloads. SwiftNZB Pro removes the limit. Everything you already downloaded stays where it is.")
            } else {
                Text("Import an NZB file to start downloading. Finished ones appear under Downloads.")
            }
        } actions: {
            if isOutOfFreeDownloads {
                // Straight to the offer. Sending them through the file picker first, only to be
                // refused by the import gate, wastes a trip.
                Button("SwiftNZB Pro") { showingPaywall = true }
                    .buttonStyle(.glassProminent)
            } else {
                Button("Add NZB") { presentImporter() }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var isOutOfFreeDownloads: Bool {
        !entitlements.isPro && entitlements.freeDownloadsRemaining == 0
    }

    /// One bottom overlay for both banners, in priority order — a finished download is the more
    /// urgent thing to say, and two floating cards must never stack on top of each other.
    @ViewBuilder
    private var bottomBanner: some View {
        if manager.recentlyCompletedJobID != nil {
            completionBanner
        } else {
            freeTierBanner
        }
    }

    /// Only appears at the very end of the free tier, and only while there is a queue to look at.
    /// Before that the count lives in Settings and nothing interrupts.
    @ViewBuilder
    private var freeTierBanner: some View {
        if !entitlements.isPro, entitlements.freeDownloadsRemaining <= 2, !manager.queueJobs.isEmpty {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("^[\(entitlements.freeDownloadsRemaining) free download](inflect: true) left")
                            .font(.subheadline.weight(.medium))
                        Text("SwiftNZB Pro removes the limit")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// A finished job leaves the queue the moment it completes. Say so, and offer the one tap that
    /// gets there, rather than letting the row silently disappear.
    @ViewBuilder
    private var completionBanner: some View {
        if let id = manager.recentlyCompletedJobID,
           let job = manager.jobs.first(where: { $0.id == id }) {
            Button {
                manager.acknowledgeCompletion()
                router.show(job.id, in: .history)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text("Finished, now in Downloads").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: id) {
                try? await Task.sleep(for: .seconds(10))
                manager.acknowledgeCompletion()
            }
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
                Section { summaryRows(active) }
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
        .padding(.vertical, 4)
    }

    /// The active download's numbers, as rows rather than a tile grid (the same move the detail
    /// page made). A stat only gets a row where it means something: a paused or post-processing
    /// job has no speed, no ETA and no open connections, and four dashes said nothing.
    @ViewBuilder
    private func summaryRows(_ job: DownloadJob) -> some View {
        let remaining = max(0, job.totalBytes - job.downloadedBytes)
        let downloading = job.status == .downloading
        if downloading {
            StatRow("Speed", Format.speed(manager.aggregateBytesPerSecond))
        }
        StatRow("Remaining", Format.bytes(remaining))
        if downloading {
            if let eta = Format.eta(remainingBytes: remaining,
                                    bytesPerSecond: manager.aggregateBytesPerSecond) {
                StatRow("ETA", eta)
            }
            StatRow("Connections", "\(manager.activeConnections)")
        }
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
