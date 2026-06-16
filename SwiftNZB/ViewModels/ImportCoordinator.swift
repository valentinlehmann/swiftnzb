//
//  ImportCoordinator.swift
//  SwiftNZB
//
//  Single entry point for .nzb imports (file picker, share sheet / Open-in, Copy-to-SwiftNZB).
//  Parses the NZB, then drives the confirmation sheet before enqueueing.
//

import Foundation
import Observation

@MainActor
@Observable
final class ImportCoordinator {
    static let shared = ImportCoordinator()

    var pendingJob: DownloadJob?
    var isPresentingConfirm = false
    var errorMessage: String?
    var isPresentingError = false

    private init() {}

    func handle(url: URL) {
        do {
            pendingJob = try NZBImporter.shared.importNZB(at: url)
            isPresentingConfirm = true
        } catch {
            errorMessage = error.localizedDescription
            isPresentingError = true
        }
    }

    func confirm(name: String, serverID: UUID?, selectedFileIDs: Set<UUID>) {
        guard let job = pendingJob else { return }
        let chosenName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? job.name : name
        let selectedFiles = job.files.filter { selectedFileIDs.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }

        // Rebuild the job from only the chosen files so totals reflect the selection.
        let newJob = DownloadJob(id: job.id, name: chosenName, files: selectedFiles,
                                 addedAt: job.addedAt, assignedServerID: serverID)
        // Remember the pick as the new default so it's preselected next time.
        if let serverID { SettingsStore.shared.settings.defaultServerID = serverID }
        DownloadManager.shared.enqueue(newJob)
        AppRouter.shared.section = .queue
        clear()
    }

    func clear() {
        pendingJob = nil
        isPresentingConfirm = false
    }
}
