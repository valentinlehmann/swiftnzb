//
//  BackgroundTaskService.swift
//  SwiftNZB
//
//  Best-effort background support. iOS won't sustain raw-socket NNTP downloads while suspended,
//  so this only (a) keeps the current segment finishing for a few seconds after backgrounding
//  via a UIKit background task, and (b) registers a BGProcessingTask the system may run
//  opportunistically (charging/idle) to nudge the queue + checkpoint. The bulk of downloading
//  happens in the foreground.
//

import Foundation
import BackgroundTasks
import UIKit

@MainActor
final class BackgroundTaskService {
    static let shared = BackgroundTaskService()

    static let processingIdentifier = "de.valentinlehmann.swiftnzb.processing"
    static let refreshIdentifier = "de.valentinlehmann.swiftnzb.refresh"

    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    /// Register handlers. Must be called before the app finishes launching.
    func registerHandlers() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingIdentifier, using: nil) { task in
            self.handleProcessing(task as? BGProcessingTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { task in
            self.handleProcessing(task as? BGProcessingTask)
            task.setTaskCompleted(success: true)
        }
    }

    /// Hold a short wind-down window so the in-flight segment can finish + checkpoint.
    func beginWindDown() {
        endWindDown()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "swiftnzb.winddown") { [weak self] in
            self?.endWindDown()
        }
    }

    func endWindDown() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    /// Ask the system to schedule an opportunistic processing window.
    func scheduleProcessing(requireExternalPower: Bool) {
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = requireExternalPower
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleProcessing(_ task: BGProcessingTask?) {
        guard let task else { return }
        // Reschedule the next opportunistic window.
        scheduleProcessing(requireExternalPower: SettingsStore.shared.settings.requireExternalPowerForBackground)

        let work = Task { @MainActor in
            await DownloadManager.shared.resumeAll()
        }
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            _ = await work.value
            task.setTaskCompleted(success: true)
        }
    }
}
