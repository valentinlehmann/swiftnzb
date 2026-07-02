//
//  JobStatus.swift
//  SwiftNZB
//

import SwiftUI

/// Lifecycle state of a download job, from import through post-processing to a terminal state.
enum JobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case downloading
    case paused
    case verifying      // PAR2 verification
    case repairing      // PAR2 Reed-Solomon repair
    case extracting     // unrar
    case completed
    case failed
    case cancelled

    var title: LocalizedStringKey {
        switch self {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .verifying: return "Verifying"
        case .repairing: return "Repairing"
        case .extracting: return "Extracting"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .verifying: return "checkmark.shield"
        case .repairing: return "wrench.and.screwdriver"
        case .extracting: return "shippingbox"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        // Orange consistently means "intentionally on hold / needs attention" (matching the
        // pause controls), grey means inert, red failure, green success, purple post-processing.
        case .queued, .cancelled: return .secondary
        case .paused: return .orange
        case .downloading: return .accentColor
        case .verifying, .repairing, .extracting: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }

    /// Actively occupying the engine / a post-processing stage.
    var isActive: Bool {
        switch self {
        case .downloading, .verifying, .repairing, .extracting: return true
        default: return false
        }
    }

    /// Reached an end state; no further work will occur without user action.
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    /// In the queue (active or waiting), as opposed to history.
    var isInQueue: Bool { !isTerminal }
}
