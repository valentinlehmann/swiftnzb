//
//  AppSection.swift
//  SwiftNZB
//

import SwiftUI

/// Top-level navigable sections. Routing the shell through this enum keeps `RootTabView`
/// (iPhone) and `SidebarRootView`/`NavigationSplitView` (iPad) interchangeable.
enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case queue
    case history
    case settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .queue: return "Queue"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .queue: return "arrow.down.circle"
        case .history: return "checkmark.circle"
        case .settings: return "gearshape"
        }
    }
}
