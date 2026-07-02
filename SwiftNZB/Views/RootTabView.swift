//
//  RootTabView.swift
//  SwiftNZB
//
//  A single adaptive TabView: on iPhone the floating tab bar, on iPad the top tab strip with a
//  toggleable sidebar. Using one component (rather than swapping TabView ↔ NavigationSplitView on
//  size-class changes) preserves navigation state through iPad multitasking resizes.
//

import SwiftUI

struct RootTabView: View {
    @State private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.section) {
            ForEach(AppSection.allCases) { section in
                Tab(section.title, systemImage: section.systemImage, value: section) {
                    NavigationStack { SectionDestinationView(section: section) }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct SectionDestinationView: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .queue: QueueView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
