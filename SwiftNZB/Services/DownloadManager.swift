//
//  DownloadManager.swift
//  SwiftNZB
//
//  The app-facing facade over the DownloadEngine. Owns the queue, runs one job at a time,
//  translates engine events into observable model updates, drives the Live Activity, and
//  finalizes completed jobs into the Files-visible completed folder.
//
//  Pause/resume is cancel + re-run: the engine reloads its checkpoint and skips resolved
//  segments, so a resumed job continues where it left off.
//

import Foundation
import Observation
import DownloadEngine
import PAR2Kit

@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    private(set) var jobs: [DownloadJob] = []
    private(set) var activeJobID: UUID?
    private(set) var aggregateBytesPerSecond: Int = 0
    private(set) var activeConnections: Int = 0
    private(set) var isWaitingForNetwork = false
    private(set) var isQueuePaused = false

    private let engine = NZBDownloadEngine()
    private var streamTask: Task<Void, Never>?
    private var perFileBytes: [String: Int] = [:]

    private enum ActiveIntent { case none, pause, cancel, network }
    private var activeIntent: ActiveIntent = .none

    private init() {}

    // MARK: - Derived collections

    var queueJobs: [DownloadJob] { jobs.filter { $0.isInQueue } }

    var historyJobs: [DownloadJob] {
        jobs.filter { $0.status.isTerminal }
            .sorted { ($0.completedAt ?? $0.addedAt) > ($1.completedAt ?? $1.addedAt) }
    }

    var activeJob: DownloadJob? { activeJobID.flatMap { id in jobs.first { $0.id == id } } }

    // MARK: - Lifecycle

    /// Called once at launch: restore the queue, reset interrupted jobs, observe the network.
    func start() {
        FileLocationService.shared.ensureBaseFolders()
        jobs = JobStore.shared.load()
        for i in jobs.indices where jobs[i].status.isActive {
            jobs[i].status = .queued   // nothing is actually running on a cold launch
            jobs[i].currentStep = nil
        }
        NetworkPathObserver.shared.onChange = { [weak self] online, expensive in
            self?.networkChanged(online: online, expensive: expensive)
        }
        NetworkPathObserver.shared.start()
        startNextIfNeeded()
    }

    // MARK: - Queue actions

    func enqueue(_ job: DownloadJob) {
        jobs.append(job)
        save()
        startNextIfNeeded()
    }

    func pause(_ id: UUID) {
        if id == activeJobID {
            activeIntent = .pause
            cancelEngine()
        } else {
            updateJob(id) { if $0.status == .queued { $0.status = .paused } }
            save()
        }
    }

    func resume(_ id: UUID) {
        updateJob(id) {
            if $0.status == .paused || $0.status == .failed {
                $0.status = .queued
                $0.errorMessage = nil
            }
        }
        save()
        startNextIfNeeded()
    }

    func cancel(_ id: UUID) {
        if id == activeJobID {
            activeIntent = .cancel
            updateJob(id) { $0.status = .cancelled }
            cancelEngine()
        } else {
            updateJob(id) { $0.status = .cancelled }
            FileLocationService.shared.removeWorkingDirectory(forJobID: id)
            save()
        }
    }

    func pauseAll() {
        isQueuePaused = true
        if activeJobID != nil {
            activeIntent = .pause
            cancelEngine()
        }
    }

    func resumeAll() {
        isQueuePaused = false
        startNextIfNeeded()
    }

    func removeFromHistory(_ id: UUID) {
        jobs.removeAll { $0.id == id && $0.status.isTerminal }
        save()
    }

    func clearHistory() {
        jobs.removeAll { $0.status.isTerminal }
        save()
    }

    func reorder(fromOffsets: IndexSet, toOffset: Int) {
        // Reorder within the queued (non-active) jobs only.
        var queued = jobs.filter { $0.status.isInQueue }
        queued.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let terminal = jobs.filter { $0.status.isTerminal }
        jobs = queued + terminal
        save()
    }

    // MARK: - Scheduling

    private func startNextIfNeeded() {
        guard !isQueuePaused, activeJobID == nil, streamTask == nil else { return }
        guard NetworkPathObserver.shared.isOnline else { return }
        if SettingsStore.shared.settings.pauseOnCellular, NetworkPathObserver.shared.isExpensive { return }
        guard let next = jobs.first(where: { $0.status == .queued }) else { return }
        guard let server = server(for: next) else {
            updateJob(next.id) {
                $0.status = .failed
                $0.errorMessage = "No Usenet server configured. Add one in Settings."
            }
            save()
            return
        }
        startJob(next, server: server)
    }

    private func startJob(_ job: DownloadJob, server: ServerAccount) {
        activeJobID = job.id
        activeIntent = .none
        isWaitingForNetwork = false
        perFileBytes = Dictionary(uniqueKeysWithValues: job.files.map { ($0.id.uuidString, $0.downloadedBytes) })

        updateJob(job.id) { $0.status = .downloading; $0.errorMessage = nil }
        if let started = jobs.first(where: { $0.id == job.id }) {
            LiveActivityService.shared.start(jobID: job.id.uuidString, state: contentState(for: started))
        }

        let spec = makeJobSpec(job)
        let config = makeServerConfig(server)

        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.engine.run(job: spec, server: config)
            for await event in stream {
                self.handle(event, jobID: job.id)
            }
        }
    }

    private func cancelEngine() {
        Task { await engine.cancel() }
    }

    // MARK: - Engine events

    private func handle(_ event: EngineEvent, jobID: UUID) {
        switch event {
        case let .progress(downloadedBytes, bytesPerSecond, connections):
            aggregateBytesPerSecond = bytesPerSecond
            activeConnections = connections
            updateJob(jobID) { $0.downloadedBytes = downloadedBytes }
            updateLiveActivity(jobID)

        case let .segmentCompleted(fileID, _, bytes):
            perFileBytes[fileID, default: 0] += bytes
            updateJob(jobID) { job in
                if let i = job.files.firstIndex(where: { $0.id.uuidString == fileID }) {
                    job.files[i].downloadedBytes = perFileBytes[fileID] ?? job.files[i].downloadedBytes
                }
            }

        case .segmentMissing:
            break  // surfaced via the per-job missing count on completion

        case let .fileCompleted(fileID, _, _):
            updateJob(jobID) { job in
                if let i = job.files.firstIndex(where: { $0.id.uuidString == fileID }) {
                    job.files[i].downloadedBytes = job.files[i].totalBytes
                }
            }

        case let .waitingForNetwork(waiting):
            isWaitingForNetwork = waiting
            updateLiveActivity(jobID)

        case let .finished(result):
            handleFinished(jobID, result: result)
        }
    }

    private func handleFinished(_ jobID: UUID, result: EngineResult) {
        streamTask = nil
        aggregateBytesPerSecond = 0
        activeConnections = 0
        let intent = activeIntent
        activeIntent = .none

        // On a successful download, keep the job active and run post-processing.
        if case let .completed(_, missing) = result {
            Task { await self.runPostProcessing(jobID, missingSegments: missing) }
            return
        }

        activeJobID = nil
        switch result {
        case .failed(let reason):
            updateJob(jobID) { $0.status = .failed; $0.errorMessage = reason }
        case .cancelled:
            switch intent {
            case .pause:
                updateJob(jobID) { if $0.status != .cancelled { $0.status = .paused } }
            case .network:
                updateJob(jobID) { if $0.status != .cancelled { $0.status = .queued } }
            case .cancel, .none:
                updateJob(jobID) { $0.status = .cancelled }
                FileLocationService.shared.removeWorkingDirectory(forJobID: jobID)
            }
        case .completed:
            break  // handled above
        }

        save()
        LiveActivityService.shared.end()
        startNextIfNeeded()
    }

    // MARK: - Post-processing (verify → repair → extract → cleanup)

    private func setStep(_ jobID: UUID, _ step: PostProcessingStep?) {
        updateJob(jobID) { job in
            job.currentStep = step
            if let step { job.status = step.jobStatus }
        }
        updateLiveActivity(jobID)
    }

    /// Runs the post-download pipeline on a completed job. Heavy work (PAR2, unrar) runs off the
    /// main actor; status/step updates happen on the main actor between phases.
    private func runPostProcessing(_ jobID: UUID, missingSegments: Int) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let workDir = FileLocationService.shared.workingDirectory(forJobID: jobID)
        let destDir = FileLocationService.shared.completedDirectory(
            for: job, mode: SettingsStore.shared.settings.folderMode)
        FileLocationService.shared.ensureDirectory(destDir)
        let settings = SettingsStore.shared.settings

        var notes: [String] = []
        if missingSegments > 0 { notes.append("\(missingSegments) article(s) were missing.") }

        // 1. PAR2 verify (+ repair).
        let par2URLs = (try? FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "par2" } ?? []
        if settings.par2VerifyEnabled, !par2URLs.isEmpty {
            setStep(jobID, .verify)
            let verify = await Task.detached { PAR2Job(par2URLs: par2URLs, directory: workDir).verify() }.value
            if !verify.isComplete {
                if settings.par2RepairEnabled, verify.isRepairable {
                    setStep(jobID, .repair)
                    let repair = await Task.detached { PAR2Job(par2URLs: par2URLs, directory: workDir).repair() }.value
                    switch repair {
                    case .repaired(let n): notes.append("Repaired \(n) block(s) with PAR2.")
                    case .insufficientRecoveryData(let miss, let avail):
                        notes.append("Not enough PAR2 data to repair (need \(miss), have \(avail)).")
                    case .failed(let reason): notes.append("PAR2 repair failed: \(reason)")
                    case .notNeeded: break
                    }
                } else if !verify.isRepairable {
                    notes.append("Files are damaged and there isn't enough PAR2 data to repair.")
                }
            }
        }

        // 2. Extract RAR archives.
        var didExtract = false
        if settings.unrarEnabled, !ArchiveExtractor.firstVolumeArchives(in: workDir).isEmpty {
            setStep(jobID, .extract)
            let outcome = await Task.detached { ArchiveExtractor.extract(in: workDir, to: destDir) }.value
            switch outcome {
            case .extracted(let n): didExtract = n > 0
            case .passwordRequired: notes.append("Archive is password-protected; not extracted.")
            case .failed(let reason): notes.append("Extraction failed: \(reason)")
            case .noArchives: break
            }
        }

        // 3. Cleanup + move remaining payload to the completed folder.
        setStep(jobID, .cleanup)
        let deleteArchives = didExtract && settings.deleteArchivesAfterExtract
        await Task.detached {
            Self.finalizeFiles(workDir: workDir, destDir: destDir, didExtract: didExtract, deleteArchives: deleteArchives)
        }.value
        FileLocationService.shared.removeWorkingDirectory(forJobID: jobID)

        // 4. Mark complete.
        updateJob(jobID) { j in
            j.status = .completed
            j.currentStep = nil
            j.completedAt = Date()
            j.downloadedBytes = j.totalBytes
            j.completedFolderRelativePath = destDir.lastPathComponent
            j.errorMessage = notes.isEmpty ? nil : notes.joined(separator: " ")
        }
        activeJobID = nil
        save()
        LiveActivityService.shared.end()
        startNextIfNeeded()
    }

    /// Move payload to `destDir`; delete or relocate archive/par2 files per settings.
    nonisolated private static func finalizeFiles(workDir: URL, destDir: URL, didExtract: Bool, deleteArchives: Bool) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let name = item.lastPathComponent
            if name == "checkpoint.json" || item.pathExtension.lowercased() == "part" { continue }
            if didExtract, isArchiveFile(name) {
                if deleteArchives { try? FileManager.default.removeItem(at: item) }
                else { moveInto(destDir, item) }
            } else {
                moveInto(destDir, item)
            }
        }
    }

    nonisolated private static func moveInto(_ destDir: URL, _ item: URL) {
        let dest = destDir.appendingPathComponent(item.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: item, to: dest)
    }

    nonisolated private static func isArchiveFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasSuffix(".rar") || lower.hasSuffix(".par2") { return true }
        // Old-style split volumes: .r00/.r01… and .001/.002…
        if let ext = lower.split(separator: ".").last, ext.count == 3 {
            if ext.first == "r", ext.dropFirst().allSatisfy(\.isNumber) { return true }
            if ext.allSatisfy(\.isNumber) { return true }
        }
        return false
    }

    private func networkChanged(online: Bool, expensive: Bool) {
        let blockedByCellular = expensive && SettingsStore.shared.settings.pauseOnCellular
        if !online || blockedByCellular {
            isWaitingForNetwork = !online
            if activeJobID != nil {
                activeIntent = .network
                cancelEngine()
            }
        } else {
            isWaitingForNetwork = false
            startNextIfNeeded()
        }
    }

    // MARK: - Live Activity

    private func contentState(for job: DownloadJob) -> DownloadActivityAttributes.ContentState {
        let remaining = max(0, job.totalBytes - job.downloadedBytes)
        return DownloadActivityAttributes.ContentState(
            jobName: job.name,
            fractionComplete: job.progress,
            bytesPerSecond: aggregateBytesPerSecond,
            etaDeadline: Format.etaDeadline(remainingBytes: remaining, bytesPerSecond: aggregateBytesPerSecond),
            stepRaw: job.currentStep?.rawValue,
            isPaused: job.status == .paused,
            isWaitingForNetwork: isWaitingForNetwork,
            additionalJobCount: max(0, jobs.filter { $0.status == .queued }.count)
        )
    }

    private func updateLiveActivity(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        LiveActivityService.shared.update(contentState(for: job))
    }

    // MARK: - Mapping app models → engine models

    private func server(for job: DownloadJob) -> ServerAccount? {
        if let id = job.assignedServerID, let account = ServerStore.shared.account(id) { return account }
        return ServerStore.shared.primaryServer
    }

    private func makeServerConfig(_ account: ServerAccount) -> ServerConfig {
        let settings = SettingsStore.shared.settings
        return ServerConfig(
            host: account.host,
            port: account.port,
            useSSL: account.useSSL,
            username: account.username.isEmpty ? nil : account.username,
            password: ServerStore.shared.password(for: account.id),
            maxConnections: max(1, min(account.maxConnections, settings.maxGlobalConnections)),
            bytesPerSecondLimit: max(0, settings.bandwidthCapKBps) * 1024
        )
    }

    private func makeJobSpec(_ job: DownloadJob) -> JobSpec {
        let files = job.files.map { file in
            FileSpec(
                id: file.id.uuidString,
                filename: file.filename,
                groups: file.groups,
                segments: file.segments.map {
                    SegmentSpec(id: $0.id.uuidString, messageID: $0.messageID, byteCount: $0.byteCount, number: $0.number)
                }
            )
        }
        let workDir = FileLocationService.shared.ensureDirectory(
            FileLocationService.shared.workingDirectory(forJobID: job.id))
        return JobSpec(id: job.id.uuidString, files: files, workingDirectory: workDir)
    }

    // MARK: - Helpers

    private func updateJob(_ id: UUID, _ mutate: (inout DownloadJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[i])
    }

    private func save() { JobStore.shared.save(jobs) }
}
