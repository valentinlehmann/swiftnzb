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

    func confirm(name: String, serverID: UUID?) {
        guard var job = pendingJob else { return }
        job.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? job.name : name
        job.assignedServerID = serverID
        // Remember the pick as the new default so it's preselected next time.
        if let serverID { SettingsStore.shared.settings.defaultServerID = serverID }
        DownloadManager.shared.enqueue(job)
        AppRouter.shared.section = .queue
        clear()
    }

    func clear() {
        pendingJob = nil
        isPresentingConfirm = false
    }
}
