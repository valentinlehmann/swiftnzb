//
//  JobStore.swift
//  SwiftNZB
//
//  Persists the job queue + history as JSON in Application Support so the app resumes its
//  state across launches. Atomic writes.
//

import Foundation

struct JobStore {
    static let shared = JobStore()

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("jobs.v1.json")
    }

    func load() -> [DownloadJob] {
        guard let data = try? Data(contentsOf: fileURL),
              let jobs = try? JSONDecoder().decode([DownloadJob].self, from: data) else {
            return []
        }
        return jobs
    }

    func save(_ jobs: [DownloadJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
