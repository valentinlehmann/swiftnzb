//
//  JobStore.swift
//  SwiftNZB
//
//  Persists the job queue + history as JSON in Application Support so the app resumes its
//  state across launches. Encoding + writing happen off the main actor on a serial queue (so a
//  large history never hitches the UI), and a corrupt file is set aside rather than silently
//  discarded and overwritten.
//

import Foundation

struct JobStore {
    static let shared = JobStore()

    private static let ioQueue = DispatchQueue(label: "de.valentinlehmann.swiftnzb.jobstore")

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("jobs.v1.json")
    }

    func load() -> [DownloadJob] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([DownloadJob].self, from: data)
        } catch {
            // Don't silently drop the user's whole queue/history (and then overwrite the file on
            // the next save). Preserve the unreadable file so it can be recovered / diagnosed.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return []
        }
    }

    /// Encode + write asynchronously on a serial queue; callers (the MainActor DownloadManager)
    /// don't block. Writes stay ordered because the queue is serial.
    func save(_ jobs: [DownloadJob]) {
        let url = fileURL
        Self.ioQueue.async {
            guard let data = try? JSONEncoder().encode(jobs) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
