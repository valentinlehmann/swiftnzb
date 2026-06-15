//
//  NZBDownloadEngine.swift
//  DownloadEngine
//
//  Orchestrates one job: a fixed pool of `maxConnections` workers (each owning an NNTPConnection)
//  pull segments from the SegmentScheduler, fetch + yEnc-decode + CRC-check them, and stream the
//  bytes to disk via the FileAssembler. Progress + completion are reported through an AsyncStream
//  of `EngineEvent`. Resume is automatic via the CheckpointStore.
//
//  Pause/resume is implemented at the app layer as cancel + re-run: a new run loads the checkpoint
//  and skips resolved segments, so this type only needs start + cancel.
//

import Foundation

public actor NZBDownloadEngine {
    public init() {}

    private var currentTask: Task<Void, Never>?

    // Per-run state (single job at a time).
    private var emit: (@Sendable (EngineEvent) -> Void)?
    private var jobID = ""
    private var workingDir: URL?
    private var assembler: FileAssembler?
    private var checkpointStore: CheckpointStore?
    private var filesByID: [String: FileSpec] = [:]

    private var downloadedBytes = 0
    private var bytesAtLastTick = 0
    private var activeConnections = 0
    private var completed: Set<String> = []
    private var missing: Set<String> = []
    private var perFileTotal: [String: Int] = [:]
    private var perFileResolved: [String: Int] = [:]
    private var perFileMissing: [String: Int] = [:]
    private var finalizedFiles: Set<String> = []

    private static let maxAttemptsPerSegment = 5
    private static let fetchTimeout: Double = 45

    // MARK: - Public API

    /// Start (or resume) a job. The returned stream yields progress and finishes with `.finished`.
    /// Cancelling the task that consumes the stream (or calling `cancel()`) stops the job.
    public func run(job: JobSpec, server: ServerConfig) -> AsyncStream<EngineEvent> {
        let (stream, continuation) = AsyncStream<EngineEvent>.makeStream()
        let task = Task { [weak self] in
            await self?.execute(job: job, server: server) { continuation.yield($0) }
            continuation.finish()
        }
        currentTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func cancel() {
        currentTask?.cancel()
    }

    // MARK: - Orchestration

    private func execute(job: JobSpec, server: ServerConfig, emit: @escaping @Sendable (EngineEvent) -> Void) async {
        resetState()
        self.emit = emit
        self.jobID = job.id
        self.workingDir = job.workingDirectory
        self.filesByID = Dictionary(uniqueKeysWithValues: job.files.map { ($0.id, $0) })

        let assembler = FileAssembler(directory: job.workingDirectory)
        let checkpointStore = CheckpointStore(directory: job.workingDirectory, jobID: job.id)
        self.assembler = assembler
        self.checkpointStore = checkpointStore

        let checkpoint = await checkpointStore.load() ?? Checkpoint(jobID: job.id)
        completed = checkpoint.completedSegmentIDs
        missing = checkpoint.missingSegmentIDs
        let resolved = checkpoint.resolvedSegmentIDs

        // Seed counters + scratch files from the checkpoint.
        for file in job.files {
            perFileTotal[file.id] = file.segments.count
            perFileResolved[file.id] = file.segments.filter { resolved.contains($0.id) }.count
            perFileMissing[file.id] = file.segments.filter { missing.contains($0.id) }.count
            downloadedBytes += file.segments
                .filter { completed.contains($0.id) }
                .reduce(0) { $0 + $1.byteCount }
            do {
                try await assembler.prepare(fileID: file.id, filename: file.filename, totalBytes: file.totalBytes)
            } catch {
                emit(.finished(.failed(reason: "Could not create scratch file: \(error.localizedDescription)")))
                return
            }
        }
        bytesAtLastTick = downloadedBytes

        let scheduler = SegmentScheduler(files: job.files, resolved: resolved)
        let remaining = await scheduler.remainingCount
        let workerCount = max(1, min(server.maxConnections, remaining == 0 ? 1 : remaining))

        // 1 Hz progress ticker (also a crude speed gauge: bytes since last tick).
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.emitProgressTick()
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask { [weak self] in
                    await self?.runWorker(server: server, scheduler: scheduler, assembler: assembler)
                }
            }
            await group.waitForAll()
        }
        ticker.cancel()

        // Finalize any fully-resolved files not already finalized incrementally (e.g. full resume).
        for file in job.files where !finalizedFiles.contains(file.id) {
            if (perFileResolved[file.id] ?? 0) >= file.segments.count {
                await finalizeFile(file.id)
            }
        }
        await assembler.closeAll()

        await checkpointStore.flush(Checkpoint(jobID: job.id, completedSegmentIDs: completed, missingSegmentIDs: missing))

        if Task.isCancelled {
            emit(.finished(.cancelled))
        } else {
            emit(.finished(.completed(downloadedBytes: downloadedBytes, missingSegments: missing.count)))
        }
    }

    // nonisolated: owns its connection as plain sequential local state and hops to the actor
    // only for shared accounting — avoids cross-isolation captures of the mutable connection.
    private nonisolated func runWorker(server: ServerConfig, scheduler: SegmentScheduler, assembler: FileAssembler) async {
        var connection: NNTPConnection?
        let maxAttempts = Self.maxAttemptsPerSegment

        while !Task.isCancelled {
            guard let item = await scheduler.next() else { break }
            var attempts = 0

            attemptLoop: while !Task.isCancelled {
                attempts += 1

                if connection == nil {
                    let candidate = NNTPConnection(config: server)
                    do {
                        try await candidate.open()
                        connection = candidate
                        await connectionOpened()
                    } catch {
                        if attempts >= maxAttempts {
                            await markMissing(item, reason: "no connection")
                            break attemptLoop
                        }
                        try? await Task.sleep(for: backoff(attempts))
                        continue
                    }
                }
                guard let conn = connection else { continue }

                do {
                    let lines = try await fetchWithTimeout(conn, messageID: item.segment.messageID)
                    let segment = try YEncDecoder.decode(bodyLines: lines)

                    if segment.crcMatches == false {
                        await conn.close(); await connectionClosed(); connection = nil
                        if attempts >= maxAttempts {
                            await markMissing(item, reason: "CRC mismatch")
                            break attemptLoop
                        }
                        try? await Task.sleep(for: backoff(attempts))
                        continue
                    }

                    try await assembler.write(fileID: item.fileID, data: segment.data, at: segment.fileOffset)
                    await markCompleted(item, bytes: segment.data.count)
                    break attemptLoop
                } catch let error as NNTPError {
                    if case .articleUnavailable = error {
                        await markMissing(item, reason: "article unavailable")
                        break attemptLoop
                    }
                    await conn.close(); await connectionClosed(); connection = nil
                    if attempts >= maxAttempts {
                        await markMissing(item, reason: "transient error")
                        break attemptLoop
                    }
                    try? await Task.sleep(for: backoff(attempts))
                } catch {
                    // Decode / disk error.
                    await conn.close(); await connectionClosed(); connection = nil
                    if attempts >= maxAttempts {
                        await markMissing(item, reason: "decode error")
                        break attemptLoop
                    }
                    try? await Task.sleep(for: backoff(attempts))
                }
            }
        }

        if let connection {
            await connection.close()
            await connectionClosed()
        }
    }

    // MARK: - Result accounting (actor-isolated)

    private func markCompleted(_ item: SegmentScheduler.WorkItem, bytes: Int) async {
        guard !completed.contains(item.segment.id) else { return }
        completed.insert(item.segment.id)
        downloadedBytes += bytes
        perFileResolved[item.fileID, default: 0] += 1
        emit?(.segmentCompleted(fileID: item.fileID, segmentID: item.segment.id, decodedBytes: bytes))
        scheduleCheckpoint()
        await maybeFinalize(item.fileID)
    }

    private func markMissing(_ item: SegmentScheduler.WorkItem, reason: String) async {
        guard !missing.contains(item.segment.id) else { return }
        missing.insert(item.segment.id)
        perFileResolved[item.fileID, default: 0] += 1
        perFileMissing[item.fileID, default: 0] += 1
        emit?(.segmentMissing(fileID: item.fileID, segmentID: item.segment.id, reason: reason))
        scheduleCheckpoint()
        await maybeFinalize(item.fileID)
    }

    private func maybeFinalize(_ fileID: String) async {
        guard let total = perFileTotal[fileID],
              (perFileResolved[fileID] ?? 0) >= total,
              !finalizedFiles.contains(fileID) else { return }
        await finalizeFile(fileID)
    }

    private func finalizeFile(_ fileID: String) async {
        guard let assembler, !finalizedFiles.contains(fileID) else { return }
        finalizedFiles.insert(fileID)
        let url = try? await assembler.finalize(fileID: fileID)
        emit?(.fileCompleted(
            fileID: fileID,
            url: url ?? workingDir ?? URL(fileURLWithPath: "/"),
            missingSegments: perFileMissing[fileID] ?? 0
        ))
    }

    private func connectionOpened() { activeConnections += 1 }
    private func connectionClosed() { activeConnections = max(0, activeConnections - 1) }

    private func emitProgressTick() {
        let delta = max(0, downloadedBytes - bytesAtLastTick)
        bytesAtLastTick = downloadedBytes
        emit?(.progress(downloadedBytes: downloadedBytes, bytesPerSecond: delta, activeConnections: activeConnections))
    }

    private func scheduleCheckpoint() {
        guard let checkpointStore else { return }
        let cp = Checkpoint(jobID: jobID, completedSegmentIDs: completed, missingSegmentIDs: missing)
        Task { await checkpointStore.scheduleSave(cp) }
    }

    private func resetState() {
        emit = nil; jobID = ""; workingDir = nil; assembler = nil; checkpointStore = nil
        filesByID = [:]
        downloadedBytes = 0; bytesAtLastTick = 0; activeConnections = 0
        completed = []; missing = []
        perFileTotal = [:]; perFileResolved = [:]; perFileMissing = [:]; finalizedFiles = []
    }

    // MARK: - Helpers

    /// Race a body fetch against a stall timeout; on timeout, close the connection to unblock it.
    private nonisolated func fetchWithTimeout(_ conn: NNTPConnection, messageID: String) async throws -> [Data] {
        let timeout = Self.fetchTimeout
        return try await withThrowingTaskGroup(of: [Data].self) { group in
            group.addTask { try await conn.fetchBody(messageID: messageID) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw NNTPError.timeout
            }
            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                await conn.close()
                group.cancelAll()
                throw error
            }
        }
    }

    /// Exponential backoff with jitter, capped at ~8s.
    private nonisolated func backoff(_ attempt: Int) -> Duration {
        let base = min(8.0, 0.25 * pow(2.0, Double(attempt - 1)))
        let jitter = Double.random(in: 0...0.4)
        return .milliseconds(Int((base + jitter) * 1000))
    }
}
