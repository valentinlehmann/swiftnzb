//
//  QueueIntents.swift
//  SwiftNZB
//
//  Siri / Shortcuts actions for the queue, plus the App Shortcuts that expose them without the
//  user building a shortcut first. App-target only: these talk to `DownloadManager` directly and
//  are not compiled into the widget (unlike `DownloadIntents`, whose Live Activity buttons are).
//

import AppIntents

struct PauseAllDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause All Downloads"
    static var description = IntentDescription("Pauses every download in the queue.")
    // Pausing is just a cancel plus a checkpoint write, which the app can do from the background.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { DownloadManager.shared.pauseAll() }
        return .result(dialog: "Downloads paused.")
    }
}

struct ResumeAllDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume All Downloads"
    static var description = IntentDescription("Opens SwiftNZB and starts the queue again.")
    /// Downloading needs the app in front. Resuming from the background would start a job iOS
    /// suspends seconds later, so this opens the app instead of pretending to work.
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { DownloadManager.shared.resumeAll() }
        return .result()
    }
}

struct DownloadStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Download Status"
    static var description = IntentDescription("Reports what SwiftNZB is downloading and how far it has got.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await MainActor.run { Self.status() })
    }

    @MainActor
    private static func status() -> IntentDialog {
        let manager = DownloadManager.shared
        if let job = manager.activeJob {
            return IntentDialog(
                LocalizedStringResource("\(job.name) is at \(Format.percent(job.progress))."))
        }
        let waiting = manager.queueJobs.count
        guard waiting > 0 else { return "Nothing is downloading." }
        return IntentDialog(
            LocalizedStringResource("^[\(waiting) download is waiting](inflect: true), none of them running."))
    }
}

/// Offered in Spotlight, Siri and the Shortcuts gallery as soon as the app is installed.
struct SwiftNZBShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseAllDownloadsIntent(),
            phrases: [
                "Pause downloads in \(.applicationName)",
                "Pause \(.applicationName)"
            ],
            shortTitle: "Pause Downloads",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeAllDownloadsIntent(),
            phrases: [
                "Resume downloads in \(.applicationName)",
                "Resume \(.applicationName)"
            ],
            shortTitle: "Resume Downloads",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: DownloadStatusIntent(),
            phrases: [
                "Check downloads in \(.applicationName)",
                "What is \(.applicationName) downloading"
            ],
            shortTitle: "Check Downloads",
            systemImageName: "arrow.down.circle"
        )
    }
}
