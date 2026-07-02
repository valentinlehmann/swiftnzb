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
import UIKit
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
    private var hasStarted = false

    private enum ActiveIntent { case none, pause, cancel, network }
    private var activeIntent: ActiveIntent = .none
    /// Set when the user hits Resume while a pause is still winding down, so the job restarts
    /// instead of settling into the paused state the wind-down was about to apply.
    private var resumeRequestedForActive = false

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
    /// Idempotent — a second scene (e.g. an extra iPad window) must not reload over live state.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        FileLocationService.shared.ensureBaseFolders()
        LiveActivityService.shared.endStaleActivities()   // clear any zombie activity from a prior run
        jobs = JobStore.shared.load()
        for i in jobs.indices where jobs[i].status.isActive {
            jobs[i].status = .queued   // nothing is actually running on a cold launch
            jobs[i].currentStep = nil
        }
        pruneHistory()
        NetworkPathObserver.shared.onChange = { [weak self] online, expensive, constrained, interfaceChanged in
            self?.networkChanged(online: online, expensive: expensive,
                                 constrained: constrained, interfaceChanged: interfaceChanged)
        }
        NetworkPathObserver.shared.start()
        save()
        startNextIfNeeded()
    }

    /// Persist resume state before the app suspends (called from the background wind-down).
    func flushForSuspension() async {
        await engine.flushCheckpoint()
        save()
    }

    /// Opportunistic background window: progress the queue if possible, but never override a
    /// user-initiated Pause All.
    func backgroundNudge() async {
        if !isQueuePaused { startNextIfNeeded() }
        await engine.flushCheckpoint()
    }

    // MARK: - Queue actions

    func enqueue(_ job: DownloadJob) {
        jobs.append(job)
        save()
        startNextIfNeeded()
    }

    func pause(_ id: UUID) {
        if id == activeJobID {
            resumeRequestedForActive = false
            activeIntent = .pause
            cancelEngine()
        } else {
            updateJob(id) { if $0.status == .queued { $0.status = .paused } }
            save()
        }
    }

    func resume(_ id: UUID) {
        // Resuming any single job implies the queue should run again.
        isQueuePaused = false
        if id == activeJobID {
            // A pause is still winding down; ask it to restart rather than settle into paused.
            resumeRequestedForActive = true
            return
        }
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
            stripSegmentsForHistory(id)
            FileLocationService.shared.removeWorkingDirectory(forJobID: id)
            save()
        }
    }

    func pauseAll() {
        isQueuePaused = true
        if activeJobID != nil {
            resumeRequestedForActive = false
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

    func removeFromHistory(_ ids: Set<UUID>) {
        jobs.removeAll { $0.status.isTerminal && ids.contains($0.id) }
        save()
    }

    func clearHistory() {
        jobs.removeAll { $0.status.isTerminal }
        save()
    }

    /// Reorder the waiting (queued/paused, non-active) jobs. The active job and history keep their
    /// positions; `offsets` are indices into `waitingQueueJobs`.
    func moveQueued(fromOffsets offsets: IndexSet, toOffset: Int) {
        var waiting = waitingQueueJobs
        waiting.move(fromOffsets: offsets, toOffset: toOffset)
        // Terminal status is authoritative: a job cancelled while still winding down (status
        // .cancelled but activeJobID still pointing at it) must land only in `terminal`, never also
        // in `active` — otherwise it would appear twice in the rebuilt array. The three buckets are
        // therefore disjoint and cover every job.
        let terminal = jobs.filter { $0.status.isTerminal }
        let active = jobs.filter { !$0.status.isTerminal && ($0.status.isActive || $0.id == activeJobID) }
        jobs = active + waiting + terminal
        save()
    }

    /// Queue jobs that aren't the active/downloading one — the reorderable set.
    var waitingQueueJobs: [DownloadJob] {
        jobs.filter { $0.isInQueue && !$0.status.isActive && $0.id != activeJobID }
    }

    // MARK: - Scheduling

    private func startNextIfNeeded() {
        guard !isQueuePaused, activeJobID == nil, streamTask == nil else { return }
        guard NetworkPathObserver.shared.isOnline else { return }
        if SettingsStore.shared.settings.pauseOnCellular,
           NetworkPathObserver.shared.isExpensive || NetworkPathObserver.shared.isConstrained { return }
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
        resumeRequestedForActive = false
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
            // Fail fast if the server can't be reached/authenticated, instead of showing a
            // download that never makes progress.
            let failure = await ServerProbe.test(config)

            // A pause/cancel/network intent may have arrived during the probe — honor it rather
            // than pressing on (which used to let a "cancelled" job keep downloading).
            if self.activeIntent != .none {
                self.handleFinished(job.id, result: .cancelled)
                return
            }
            if let failure {
                // Offline probe failures are transient: requeue and wait for the network instead
                // of permanently failing the job.
                if !NetworkPathObserver.shared.isOnline {
                    self.activeIntent = .network
                    self.handleFinished(job.id, result: .cancelled)
                    return
                }
                self.handleFinished(job.id, result: .failed(reason: failure))
                return
            }
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
            // Flush accumulated per-file byte counts here (once/sec) rather than on every segment,
            // so a high-throughput job doesn't invalidate the whole list hundreds of times a second.
            updateJob(jobID) { job in
                job.downloadedBytes = downloadedBytes
                for i in job.files.indices {
                    if let bytes = perFileBytes[job.files[i].id.uuidString] {
                        job.files[i].downloadedBytes = bytes
                    }
                }
            }
            updateLiveActivity(jobID)

        case let .segmentCompleted(fileID, _, bytes):
            // Cheap: just accumulate. The UI/model update is coalesced into the 1 Hz progress tick.
            perFileBytes[fileID, default: 0] += bytes

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
            haptic(.error)
            LiveActivityService.shared.end()
        case .cancelled:
            switch intent {
            case .pause:
                if resumeRequestedForActive {
                    resumeRequestedForActive = false
                    updateJob(jobID) { if $0.status != .cancelled { $0.status = .queued } }
                } else {
                    updateJob(jobID) { if $0.status != .cancelled { $0.status = .paused } }
                    // Keep the Live Activity alive (paused) so its Resume button stays reachable;
                    // it's replaced if another queued job starts below.
                    updateLiveActivity(jobID)
                }
            case .network:
                updateJob(jobID) { if $0.status != .cancelled { $0.status = .queued } }
                if !NetworkPathObserver.shared.isOnline {
                    isWaitingForNetwork = true
                    updateLiveActivity(jobID)   // show "waiting for network" rather than dismissing
                }
            case .cancel, .none:
                updateJob(jobID) { $0.status = .cancelled }
                stripSegmentsForHistory(jobID)
                FileLocationService.shared.removeWorkingDirectory(forJobID: jobID)
                LiveActivityService.shared.end()
            }
        case .completed:
            break  // handled above
        }

        save()
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

    /// True if the user cancelled this job (cancel sets `.cancelled` synchronously). Used to bail
    /// out of the post-processing pipeline between phases.
    private func wasCancelled(_ jobID: UUID) -> Bool {
        jobs.first(where: { $0.id == jobID })?.status == .cancelled
    }

    private func finishCancelledPostProcessing(_ jobID: UUID) {
        activeJobID = nil
        stripSegmentsForHistory(jobID)
        FileLocationService.shared.removeWorkingDirectory(forJobID: jobID)
        save()
        LiveActivityService.shared.end()
        startNextIfNeeded()
    }

    /// Runs the post-download pipeline on a completed job. Heavy work (PAR2, unrar) runs off the
    /// main actor; status/step updates happen on the main actor between phases. Honors a cancel
    /// issued mid-pipeline instead of force-marking the job completed at the end.
    private func runPostProcessing(_ jobID: UUID, missingSegments: Int) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { activeJobID = nil; startNextIfNeeded(); return }
        if wasCancelled(jobID) { finishCancelledPostProcessing(jobID); return }

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
            if wasCancelled(jobID) { finishCancelledPostProcessing(jobID); return }
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
            if wasCancelled(jobID) { finishCancelledPostProcessing(jobID); return }
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
        if wasCancelled(jobID) { finishCancelledPostProcessing(jobID); return }
        setStep(jobID, .cleanup)
        let deleteArchives = didExtract && settings.deleteArchivesAfterExtract
        await Task.detached {
            Self.finalizeFiles(workDir: workDir, destDir: destDir, didExtract: didExtract, deleteArchives: deleteArchives)
        }.value
        FileLocationService.shared.removeWorkingDirectory(forJobID: jobID)

        if wasCancelled(jobID) { finishCancelledPostProcessing(jobID); return }

        // 4. Mark complete.
        updateJob(jobID) { j in
            j.status = .completed
            j.currentStep = nil
            j.completedAt = Date()
            j.downloadedBytes = j.totalBytes
            j.completedFolderRelativePath = destDir.lastPathComponent
            j.errorMessage = notes.isEmpty ? nil : notes.joined(separator: " ")
            j.files = j.files.map { var f = $0; f.segments = []; return f }   // free per-segment metadata
        }
        if let serverID = server(for: job)?.id {
            ServerUsageStore.shared.record(serverID: serverID, bytes: job.totalBytes)
        }
        activeJobID = nil
        haptic(.success)
        pruneHistory()
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

    private func networkChanged(online: Bool, expensive: Bool, constrained: Bool, interfaceChanged: Bool) {
        let blockedByPolicy = (expensive || constrained) && SettingsStore.shared.settings.pauseOnCellular
        if !online || blockedByPolicy {
            isWaitingForNetwork = !online
            if activeJobID != nil {
                activeIntent = .network
                cancelEngine()
            }
        } else {
            isWaitingForNetwork = false
            if interfaceChanged, activeJobID != nil {
                // Interface handoff (e.g. Wi-Fi → cellular): the in-flight sockets are bound to the
                // now-dead path and would stall until each request times out. Restart the job so it
                // rebuilds connections on the new path; the checkpoint means no re-download.
                activeIntent = .network
                cancelEngine()
            } else {
                startNextIfNeeded()
            }
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

    // MARK: - History maintenance

    /// Completed and cancelled jobs never resume, so drop their per-segment metadata to keep
    /// `jobs.v1.json` from growing without bound on heavy use. (Failed/paused jobs keep segments so
    /// they remain resumable.)
    private func stripSegmentsForHistory(_ jobID: UUID) {
        updateJob(jobID) { job in
            guard job.status == .completed || job.status == .cancelled else { return }
            job.files = job.files.map { var f = $0; f.segments = []; return f }
        }
    }

    private func pruneHistory() {
        let days = SettingsStore.shared.settings.keepCompletedHistoryDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        jobs.removeAll { $0.status.isTerminal && ($0.completedAt ?? $0.addedAt) < cutoff }
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: - Mapping app models → engine models

    private func server(for job: DownloadJob) -> ServerAccount? {
        if let id = job.assignedServerID, let account = ServerStore.shared.account(id) { return account }
        if let id = SettingsStore.shared.settings.defaultServerID, let account = ServerStore.shared.account(id) { return account }
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
