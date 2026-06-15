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
    private init() {}
}
