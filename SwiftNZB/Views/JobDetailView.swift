//
//  JobDetailView.swift
//  SwiftNZB
//

import SwiftUI

struct JobDetailView: View {
    let jobID: UUID
    @State private var manager = DownloadManager.shared
    @State private var showingFiles = false
    @State private var confirmingCancel = false

    private var job: DownloadJob? { manager.jobs.first { $0.id == jobID } }

    var body: some View {
        if let job {
            List {
                Section { header(job) }
                Section { statTiles(job) }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if let step = job.currentStep {
                    Section { stageBanner(step) }
                }
                Section { controls(job) }
                    .listRowBackground(Color.clear)
                if let error = job.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle").font(.callout) }
                }
                if !job.files.isEmpty {
                    Section("Files") {
                        ForEach(job.files) { FileProgressRow(file: $0) }
                    }
                }
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(job.status.title)
            .sheet(isPresented: $showingFiles) {
                NavigationStack { FileBrowserView(job: job) }
                    .presentationSizing(.form)
            }
            .confirmationDialog("Cancel this download?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Cancel Download", role: .destructive) { manager.cancel(jobID) }
                Button("Keep Downloading", role: .cancel) {}
            } message: {
                Text("The partially downloaded files will be deleted.")
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
                Text(verbatim: Format.percent(job.progress))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.default, value: job.progress)
            }
            ProgressView(value: job.progress)
                .tint(job.status.tint)
                .animation(.default, value: job.progress)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statTiles(_ job: DownloadJob) -> some View {
        let downloading = job.status == .downloading && job.id == manager.activeJobID
        let remaining = max(0, job.totalBytes - job.downloadedBytes)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile("Downloaded", Format.bytes(job.downloadedBytes), systemImage: "arrow.down.circle")
                StatTile("Total", Format.bytes(job.totalBytes), systemImage: "doc")
            }
            HStack(spacing: 10) {
                StatTile("Speed", downloading ? Format.speed(manager.aggregateBytesPerSecond) : "—",
                         systemImage: "speedometer", tint: downloading ? .accentColor : .secondary)
                StatTile("ETA",
                         downloading ? (Format.eta(remainingBytes: remaining, bytesPerSecond: manager.aggregateBytesPerSecond) ?? "—") : "—",
                         systemImage: "clock")
            }
        }
    }

    @ViewBuilder
    private func stageBanner(_ step: PostProcessingStep) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(step.title).font(.callout.weight(.medium))
            Spacer()
        }
        .listRowBackground(Color.purple.opacity(0.08))
    }

    @ViewBuilder
    private func controls(_ job: DownloadJob) -> some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 24) {
                Spacer()
                switch job.status {
                case .downloading, .queued:
                    CircleActionButton(systemImage: "pause.fill", label: "Pause", tint: .orange, prominent: true) { manager.pause(job.id) }
                case .paused, .failed:
                    CircleActionButton(systemImage: "play.fill", label: "Resume", tint: .green, prominent: true) { manager.resume(job.id) }
                case .completed:
                    CircleActionButton(systemImage: "folder", label: "Show Files", tint: .accentColor, prominent: true) { showingFiles = true }
                default:
                    EmptyView()
                }
                if !job.status.isTerminal {
                    CircleActionButton(systemImage: "xmark", label: "Cancel Download", tint: .red, role: .destructive) { confirmingCancel = true }
                }
                Spacer()
            }
        }
    }
}
