//
//  RootTabView.swift
//  SwiftNZB
//
//  Size-class adaptive shell: TabView on iPhone, NavigationSplitView on iPad. Both route
//  through SectionDestinationView so the screens stay interchangeable.
//

import SwiftUI

struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var router = AppRouter.shared

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(AppSection.allCases, selection: sidebarSelection) { section in
                    Label(section.title, systemImage: section.systemImage).tag(section)
                }
                .navigationTitle("SwiftNZB")
            } detail: {
                NavigationStack { SectionDestinationView(section: router.section) }
            }
        } else {
            TabView(selection: $router.section) {
                ForEach(AppSection.allCases) { section in
                    NavigationStack { SectionDestinationView(section: section) }
                        .tabItem { Label(section.title, systemImage: section.systemImage) }
                        .tag(section)
                }
            }
        }
    }

    private var sidebarSelection: Binding<AppSection?> {
        Binding(get: { router.section }, set: { if let value = $0 { router.section = value } })
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
