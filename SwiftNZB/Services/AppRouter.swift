//
//  AppRouter.swift
//  SwiftNZB
//

import Foundation
import Observation

/// Holds the selected top-level section so imports / deep links can route the shell.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var section: AppSection = .queue
    /// Navigation stack per section, so a deep link ("your download finished") can push the job's
    /// own screen instead of dropping the user on a list to go find it.
    var paths: [AppSection: [UUID]] = [:]

    private init() {}

    /// Switch to `section` and open `jobID` there.
    func show(_ jobID: UUID, in section: AppSection) {
        self.section = section
        paths[section] = [jobID]
    }
}
