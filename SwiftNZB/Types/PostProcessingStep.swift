//
//  PostProcessingStep.swift
//  SwiftNZB
//

import SwiftUI

/// A stage in the post-download pipeline. Surfaced in the job detail UI and the Live Activity
/// (`DownloadActivityAttributes.ContentState.stepRaw` carries the `rawValue`).
enum PostProcessingStep: String, Codable, CaseIterable, Sendable {
    case assemble       // concatenate decoded segments into the original files
    case verify         // PAR2 verification
    case repair         // PAR2 Reed-Solomon repair
    case extract        // unrar
    case cleanup        // delete intermediate archives / scratch files

    var title: LocalizedStringKey {
        switch self {
        case .assemble: return "Assembling"
        case .verify: return "Verifying"
        case .repair: return "Repairing"
        case .extract: return "Extracting"
        case .cleanup: return "Cleaning up"
        }
    }

    /// The job status that corresponds to this step while it runs.
    var jobStatus: JobStatus {
        switch self {
        case .assemble: return .downloading
        case .verify: return .verifying
        case .repair: return .repairing
        case .extract: return .extracting
        case .cleanup: return .extracting
        }
    }
}
