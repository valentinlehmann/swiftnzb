//
//  NotificationService.swift
//  SwiftNZB
//
//  Tells the user a download finished or failed when they aren't looking at the app. Downloads
//  only run while SwiftNZB is in front, but post-processing (PAR2 repair, unrar of a large set)
//  can take minutes past the last article, and a failure otherwise stays invisible until the app
//  is reopened.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private var didRequest = false

    private init() {}

    /// Ask provisionally: the first notification is delivered quietly to Notification Center with
    /// no permission dialog, and the user decides from there whether to keep it. Nothing to
    /// explain up front, and no prompt on a screen the user hasn't reached yet.
    func requestAuthorizationIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        }
    }

    func notifyFinished(name: String, note: String?) {
        post(title: String(localized: "Download finished"),
             body: note.map { "\(name)\n\($0)" } ?? name,
             id: "finished")
    }

    func notifyFailed(name: String, reason: String?) {
        post(title: String(localized: "Download failed"),
             body: reason.map { "\(name)\n\($0)" } ?? name,
             id: "failed")
    }

    /// Skipped while the app is in front: the queue, the banner and the Live Activity already say
    /// this, and a notification on top of them is noise.
    private func post(title: String, body: String, id: String) {
        guard SettingsStore.shared.settings.notifyOnFinish else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(id).\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
