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
    /// True when the screenshot lane launched the app with `-startSection`. Debug-only affordances
    /// hide themselves so they cannot end up in a store screenshot.
    static let isScreenshotRun: Bool = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "startSection") != nil
        #else
        return false
        #endif
    }()

    var section: AppSection = {
        #if DEBUG
        // Lets the screenshot lane open straight onto a tab: `simctl launch … -startSection
        // history`. Foundation maps `-key value` launch arguments into UserDefaults, so this needs
        // no argument parsing. Compiled out of Release, so it cannot ship.
        if let raw = UserDefaults.standard.string(forKey: "startSection"),
           let section = AppSection(rawValue: raw) {
            return section
        }
        #endif
        return .queue
    }()
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
