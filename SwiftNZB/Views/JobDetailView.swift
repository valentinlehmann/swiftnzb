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
    @State private var isExtracting = false
    @State private var askingForPassword = false
    @State private var passwordInput = ""
    @State private var expandedGroups: Set<FileKind> = []

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
                fileSections(job)
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(job.status.title)
            .sheet(isPresented: $showingFiles) {
                NavigationStack { FileBrowserView(job: job) }
                    .presentationSizing(.form)
            }
            .alert("Archive Password", isPresented: $askingForPassword) {
                TextField("Password", text: $passwordInput)
                Button("Extract") {
                    let password = passwordInput
                    passwordInput = ""
                    Task { await extract(jobID, password: password) }
                }
                Button("Cancel", role: .cancel) { passwordInput = "" }
            } message: {
                Text("This archive is password-protected. NZBs from an indexer usually carry the password; this one didn't.")
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

    /// The file list, split by role. Content first and always expanded — it is what the user came
    /// for; archive volumes and PAR2 recovery data collapse behind a count so a 21-file release
    /// doesn't bury the one file that matters. An archive-only release has no content file of its
    /// own, so point at what extraction produced instead.
    @ViewBuilder
    private func fileSections(_ job: DownloadJob) -> some View {
        let byKind = Dictionary(grouping: job.files, by: \.kind)
        let content = byKind[.content] ?? []

        if !content.isEmpty {
            Section(FileKind.content.title) {
                ForEach(content) { FileProgressRow(file: $0) }
            }
        } else if job.status == .completed, !job.files.isEmpty {
            Section(FileKind.content.title) {
                Button { showingFiles = true } label: {
                    Label("Show Extracted Files", systemImage: "folder")
                }
            }
        }

        ForEach([FileKind.archivePart, .parity], id: \.self) { kind in
            if let files = byKind[kind], !files.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: expansion(kind)) {
                        ForEach(files) { FileProgressRow(file: $0) }
                    } label: {
                        HStack {
                            Label(kind.title, systemImage: kind.groupSystemImage)
                                .font(.subheadline)
                            Spacer()
                            // Text("\(count)") would pick up a locale thousands separator.
                            Text(verbatim: "\(files.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func expansion(_ kind: FileKind) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(kind) },
            set: { expanded in
                if expanded { expandedGroups.insert(kind) } else { expandedGroups.remove(kind) }
            }
        )
    }

    private func extract(_ jobID: UUID, password: String?) async {
        isExtracting = true
        let needsPassword = await manager.extractAgain(jobID, password: password)
        isExtracting = false
        if needsPassword { askingForPassword = true }
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
                    // Extraction can fail for a fixable reason (password, damaged volume) while the
                    // archives survive in the completed folder — retry without re-downloading.
                    if job.files.contains(where: { $0.filename.lowercased().hasSuffix(".rar") }) {
                        if isExtracting {
                            ProgressView().frame(width: 44, height: 44)
                        } else {
                            CircleActionButton(systemImage: "shippingbox", label: "Extract Again", tint: .purple) {
                                Task { await extract(job.id, password: nil) }
                            }
                        }
                    }
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
