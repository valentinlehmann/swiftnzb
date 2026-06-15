//
//  SegmentScheduler.swift
//  DownloadEngine
//
//  The shared work queue. Hands out segments to pool workers; already-resolved segments (from a
//  resumed checkpoint) are skipped. Each worker fully resolves the segment it pulls (retrying on
//  its own / a fresh connection), so the scheduler stays a simple thread-safe queue — the seam
//  where multi-server failover slots in later (requeue against the next server by priority).
//

import Foundation

actor SegmentScheduler {
    struct WorkItem: Sendable {
        let fileID: String
        let filename: String
        let segment: SegmentSpec
    }

    private var pending: [WorkItem]
    private var cursor = 0

    init(files: [FileSpec], resolved: Set<String>) {
        pending = files.flatMap { file in
            file.segments
                .filter { !resolved.contains($0.id) }
                .sorted { $0.number < $1.number }
                .map { WorkItem(fileID: file.id, filename: file.filename, segment: $0) }
        }
    }

    func next() -> WorkItem? {
        guard cursor < pending.count else { return nil }
        defer { cursor += 1 }
        return pending[cursor]
    }

    var remainingCount: Int { max(0, pending.count - cursor) }
    var totalCount: Int { pending.count }
}
