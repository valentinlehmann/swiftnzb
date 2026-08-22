//
//  JobDetailView.swift
//  SwiftNZB
//

import SwiftUI

struct JobDetailView: View {
    let jobID: UUID
    @State private var manager = DownloadManager.shared
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
                statRows(job)
                if let step = job.currentStep {
                    Section { stageBanner(step) }
                }
                if hasControls(job) {
                    Section { controls(job) }
                        .listRowBackground(Color.clear)
                }
                if let error = job.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle").font(.callout) }
                }
                fileSections(job)
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(job.status.title)
            .alert("Archive Password", isPresented: $askingForPassword) {
                TextField("Password", text: $passwordInput)
                Button("Extract") {
                    let password = passwordInput
                    passwordInput = ""
                    Task { await extract(jobID, password: password) }
                }
                Button("Cancel", role: .cancel) { passwordInput = "" }
            } message: {
                Text("This archive needs a password. Indexer NZBs usually carry one, this one didn't.")
            }
            .confirmationDialog("Cancel this download?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Cancel Download", role: .destructive) { manager.cancel(jobID) }
                Button("Keep Downloading", role: .cancel) {}
            } message: {
                Text("SwiftNZB deletes the partly downloaded files.")
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

    /// Plain rows in their own section instead of a tile grid: a `LabeledContent` list is what the
    /// rest of iOS uses for this, and it lets each stat show up only when it means something.
    /// A finished download has no speed and no ETA, so those rows are gone rather than showing a
    /// dash, and its downloaded byte count equals its size, so only the size is worth a row.
    @ViewBuilder
    private func statRows(_ job: DownloadJob) -> some View {
        let live = job.status == .downloading && job.id == manager.activeJobID
        let remaining = max(0, job.totalBytes - job.downloadedBytes)
        Section("Details") {
            if job.status == .completed {
                LabeledContent("Size") { statValue(Format.bytes(job.totalBytes)) }
                if let completedAt = job.completedAt {
                    LabeledContent("Finished") {
                        Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            } else {
                LabeledContent("Downloaded") { statValue(Format.bytes(job.downloadedBytes)) }
                LabeledContent("Total") { statValue(Format.bytes(job.totalBytes)) }
                if live {
                    LabeledContent("Speed") { statValue(Format.speed(manager.aggregateBytesPerSecond)) }
                    if let eta = Format.eta(remainingBytes: remaining,
                                            bytesPerSecond: manager.aggregateBytesPerSecond) {
                        LabeledContent("ETA") { statValue(eta) }
                    }
                }
            }
        }
    }

    /// Byte counts and speeds use `Text(verbatim:)` so they keep their own formatting.
    private func statValue(_ value: String) -> some View {
        Text(verbatim: value)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.default, value: value)
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

    /// The file list, split by role: content first and prominent, archive volumes and PAR2 data
    /// collapsed behind a count so a 22-file release doesn't bury the one file that matters.
    ///
    /// A finished job lists what is actually on disk — the extracted video is the product, and it
    /// is not an NZB entry at all, so `job.files` can't show it. While the job runs there is
    /// nothing on disk yet worth showing, so those rows track per-file progress instead.
    @ViewBuilder
    private func fileSections(_ job: DownloadJob) -> some View {
        if job.status == .completed {
            outputSections(in: outputFolder(job))
        } else {
            progressSections(job)
        }
    }

    @ViewBuilder
    private func outputSections(in folder: URL) -> some View {
        let files = contents(of: folder)
        if files.isEmpty {
            Section(FileKind.content.title) {
                Label("The output folder is empty.", systemImage: "folder")
                    .foregroundStyle(.secondary)
            }
        } else {
            let byKind = Dictionary(grouping: files) { FileKind.of(filename: $0.lastPathComponent) }
            if let content = byKind[.content], !content.isEmpty {
                Section(FileKind.content.title) {
                    ForEach(content, id: \.self) { outputRow($0) }
                }
            }
            ForEach([FileKind.archivePart, .parity], id: \.self) { kind in
                if let group = byKind[kind], !group.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: expansion(kind)) {
                            ForEach(group, id: \.self) { outputRow($0) }
                        } label: {
                            FileKindGroupLabel(kind: kind, count: group.count)
                        }
                    }
                }
            }
        }
    }

    /// One output file: tapping it shares/exports the file itself.
    private func outputRow(_ url: URL) -> some View {
        let kind = FileKind.of(filename: url.lastPathComponent)
        return ShareLink(item: url) {
            HStack {
                Image(systemName: FileKind.symbol(forFilename: url.lastPathComponent))
                    .foregroundStyle(kind == .content ? .primary : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    // Middle truncation so the file type stays readable on a long name.
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: Format.bytes(fileSize(url)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func progressSections(_ job: DownloadJob) -> some View {
        let byKind = Dictionary(grouping: job.files, by: \.kind)
        if let content = byKind[.content], !content.isEmpty {
            Section(FileKind.content.title) {
                ForEach(content) { FileProgressRow(file: $0) }
            }
        }
        ForEach([FileKind.archivePart, .parity], id: \.self) { kind in
            if let files = byKind[kind], !files.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: expansion(kind)) {
                        ForEach(files) { FileProgressRow(file: $0) }
                    } label: {
                        FileKindGroupLabel(kind: kind, count: files.count)
                    }
                }
            }
        }
    }

    /// Where a finished job's files live (the recorded path, else the current layout preference).
    private func outputFolder(_ job: DownloadJob) -> URL {
        if let relative = job.completedFolderRelativePath {
            return FileLocationService.shared.completeFolder.appendingPathComponent(relative, isDirectory: true)
        }
        return FileLocationService.shared.completedDirectory(
            for: job, mode: SettingsStore.shared.settings.folderMode)
    }

    private func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Whether `controls` renders any button at all — a finished download with nothing to retry has
    /// none, and an empty glass row reads as a glitch.
    private func hasControls(_ job: DownloadJob) -> Bool {
        switch job.status {
        case .downloading, .queued, .paused, .failed: return true
        case .completed: return canExtractAgain(job)
        default: return !job.status.isTerminal
        }
    }

    private func canExtractAgain(_ job: DownloadJob) -> Bool {
        job.files.contains { $0.kind == .archivePart }
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
                    // Extraction can fail for a fixable reason (password, damaged volume) while the
                    // archives survive in the completed folder — retry without re-downloading.
                    if canExtractAgain(job) {
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
