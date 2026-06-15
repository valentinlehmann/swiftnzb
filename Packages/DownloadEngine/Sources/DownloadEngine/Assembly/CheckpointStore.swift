//
//  CheckpointStore.swift
//  DownloadEngine
//
//  Persists which segments are done / permanently missing so a job survives app suspension or
//  relaunch and resumes without re-downloading. The on-disk `.part` files are authoritative; the
//  checkpoint is a fast index that lets the scheduler skip resolved work. Writes are atomic and
//  debounced.
//

import Foundation

/// Serializable resume state for one job.
public struct Checkpoint: Codable, Sendable {
    public var jobID: String
    public var completedSegmentIDs: Set<String>
    public var missingSegmentIDs: Set<String>

    public init(jobID: String, completedSegmentIDs: Set<String> = [], missingSegmentIDs: Set<String> = []) {
        self.jobID = jobID
        self.completedSegmentIDs = completedSegmentIDs
        self.missingSegmentIDs = missingSegmentIDs
    }

    /// Segments already resolved (won't be re-fetched).
    public var resolvedSegmentIDs: Set<String> { completedSegmentIDs.union(missingSegmentIDs) }
}

actor CheckpointStore {
    private let url: URL
    private var pendingSaveTask: Task<Void, Never>?
    private static let debounce: Duration = .seconds(2)

    init(directory: URL, jobID: String) {
        self.url = directory.appendingPathComponent("checkpoint.json")
    }

    func load() -> Checkpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }

    /// Debounced save — repeated calls coalesce into one write after a short quiet period.
    func scheduleSave(_ checkpoint: Checkpoint) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [url] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            Self.write(checkpoint, to: url)
        }
    }

    /// Immediate, synchronous flush (call on pause / wind-down before suspension).
    func flush(_ checkpoint: Checkpoint) {
        pendingSaveTask?.cancel()
        Self.write(checkpoint, to: url)
    }

    private static func write(_ checkpoint: Checkpoint, to url: URL) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
