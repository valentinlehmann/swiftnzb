//
//  LiveActivityService.swift
//  SwiftNZB
//
//  ActivityKit wrapper for the download Live Activity. The app updates it while running
//  (foreground + the brief background wind-down); sustained suspended updates would require
//  APNs push (a later phase).
//

import Foundation
import ActivityKit

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<DownloadActivityAttributes>?

    private init() {}

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(jobID: String, state: DownloadActivityAttributes.ContentState) {
        guard isAvailable else { return }
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        let attributes = DownloadActivityAttributes(jobID: jobID)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(_ state: DownloadActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        let final = activity.content.state
        self.activity = nil
        Task { await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate) }
    }
}
