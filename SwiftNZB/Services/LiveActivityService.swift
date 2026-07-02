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

    /// End any Live Activities left over from a previous process (e.g. the app was killed while a
    /// download was showing). Otherwise a zombie activity lingers on the Lock Screen with no way
    /// to control it. Call once at launch, before starting anything new.
    func endStaleActivities() {
        for activity in Activity<DownloadActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        self.activity = nil
    }

    func start(jobID: String, state: DownloadActivityAttributes.ContentState) {
        guard isAvailable else { return }
        if let activity, activity.attributes.jobID == jobID {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        // A different job is taking over the (single) activity slot: end the old one first.
        if let activity {
            let old = activity
            Task { await old.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
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
