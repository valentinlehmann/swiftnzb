//
//  DownloadJob.swift
//  SwiftNZB
//

import Foundation

/// One imported NZB turned into a unit of work: a queue of files/segments to download and
/// post-process. The central persisted model (see `JobStore`).
struct DownloadJob: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Display name, derived from the NZB filename / `<head><meta type="name">`.
    var name: String
    var status: JobStatus
    var files: [NZBFileSummary]
    /// Declared total size across all files.
    var totalBytes: Int
    /// Bytes downloaded + decoded so far across all files.
    var downloadedBytes: Int
    var addedAt: Date
    var completedAt: Date?
    /// Non-nil while post-processing; drives the detail UI + Live Activity stage label.
    var currentStep: PostProcessingStep?
    var errorMessage: String?
    /// nil = use the default/all enabled servers; otherwise pin to one `ServerAccount`.
    var assignedServerID: UUID?
    /// Relative path (under the completed folder) where output landed — for "Show in Files".
    var completedFolderRelativePath: String?

    var progress: Double {
        totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : 0
    }

    var isInQueue: Bool { status.isInQueue }

    init(
        id: UUID = UUID(),
        name: String,
        status: JobStatus = .queued,
        files: [NZBFileSummary],
        addedAt: Date = Date(),
        assignedServerID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.files = files
        self.totalBytes = files.reduce(0) { $0 + $1.totalBytes }
        self.downloadedBytes = files.reduce(0) { $0 + $1.downloadedBytes }
        self.addedAt = addedAt
        self.completedAt = nil
        self.currentStep = nil
        self.errorMessage = nil
        self.assignedServerID = assignedServerID
        self.completedFolderRelativePath = nil
    }

    // Migration-safe decoder.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Download"
        status = try c.decodeIfPresent(JobStatus.self, forKey: .status) ?? .queued
        files = try c.decodeIfPresent([NZBFileSummary].self, forKey: .files) ?? []
        totalBytes = try c.decodeIfPresent(Int.self, forKey: .totalBytes)
            ?? files.reduce(0) { $0 + $1.totalBytes }
        downloadedBytes = try c.decodeIfPresent(Int.self, forKey: .downloadedBytes)
            ?? files.reduce(0) { $0 + $1.downloadedBytes }
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        currentStep = try c.decodeIfPresent(PostProcessingStep.self, forKey: .currentStep)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        assignedServerID = try c.decodeIfPresent(UUID.self, forKey: .assignedServerID)
        completedFolderRelativePath = try c.decodeIfPresent(String.self, forKey: .completedFolderRelativePath)
    }
}
