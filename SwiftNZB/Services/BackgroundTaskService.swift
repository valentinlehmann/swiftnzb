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

    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    /// Register handlers. Must be called before the app finishes launching. The scheduler invokes
    /// the handler on a background queue, so we immediately hop to the main actor (all of our
    /// state — SettingsStore, DownloadManager — is main-actor isolated).
    func registerHandlers() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in Self.shared.handleProcessing(processing) }
        }
    }

    /// Hold a short wind-down window so the in-flight segment can finish + checkpoint.
    func beginWindDown() {
        endWindDown()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "swiftnzb.winddown") { [weak self] in
            // Expiration: persist resume state before the app is suspended, then release the task.
            Task { @MainActor in
                await DownloadManager.shared.flushForSuspension()
                self?.endWindDown()
            }
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

    private func handleProcessing(_ task: BGProcessingTask) {
        // Reschedule the next opportunistic window.
        scheduleProcessing(requireExternalPower: SettingsStore.shared.settings.requireExternalPowerForBackground)

        let work = Task { @MainActor in
            // Only nudge the queue forward — never override the user's Pause All. Downloading can't
            // be sustained under suspension, so this mostly ensures state is progressed/persisted.
            await DownloadManager.shared.backgroundNudge()
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in await DownloadManager.shared.flushForSuspension() }
        }
        Task { @MainActor in
            _ = await work.value
            task.setTaskCompleted(success: true)
        }
    }
}
