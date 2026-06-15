//
//  DownloadActivityAttributes.swift
//  SwiftNZB
//
//  Shared between the app and the SwiftNZBWidgets extension (see project.yml).
//  MUST stay dependency-free (no app/service types) so the widget compiles standalone.
//

import Foundation
import ActivityKit

/// Live Activity describing the active download (or post-processing) job.
struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Display name of the job currently shown in the activity.
        var jobName: String
        /// Overall progress, 0...1 — drives the determinate `ProgressView`.
        var fractionComplete: Double
        /// Current download throughput (bytes/sec). 0 while post-processing or stalled.
        var bytesPerSecond: Int
        /// When the download is expected to finish; the widget renders a self-updating
        /// countdown via `Text(timerInterval:)`, so ETA advances without per-second pushes.
        /// nil when unknown (stalled / post-processing).
        var etaDeadline: Date?
        /// `PostProcessingStep.rawValue` while post-processing (verify/repair/extract), else nil.
        var stepRaw: String?
        /// Whether the job is paused (download parked or user-paused).
        var isPaused: Bool
        /// True when the network is unavailable and the queue is waiting to resume.
        var isWaitingForNetwork: Bool
        /// Number of additional active/queued jobs beyond the one shown ("+N more").
        var additionalJobCount: Int
    }

    /// Stable identifier of the job this activity tracks, so interactive intents can target it.
    var jobID: String
}
