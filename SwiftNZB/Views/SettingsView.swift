//
//  SettingsView.swift
//  SwiftNZB
//
//  Root settings menu. Each category pushes a focused sub-screen with per-option explanations.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                row("Servers", "Accounts and the default server", "server.rack") { ServersSettingsView() }
                row("Connections", "Parallel connections per download", "point.3.connected.trianglepath.dotted") { ConnectionsSettingsView() }
                row("Bandwidth", "Speed limit and cellular use", "speedometer") { BandwidthSettingsView() }
                row("Post-Processing", "PAR2 repair and RAR extraction", "wand.and.stars") { PostProcessingSettingsView() }
                row("Files & Storage", "Output location and free space", "folder") { StorageSettingsView() }
                row("Background", "Downloading while the app is closed", "bolt.badge.clock") { BackgroundSettingsView() }
            }
            Section {
                row("About", nil, "info.circle") { AboutView() }
            }
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func row<Destination: View>(
        _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey?, _ systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}
