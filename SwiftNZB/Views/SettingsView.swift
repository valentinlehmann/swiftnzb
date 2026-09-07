//
//  SettingsView.swift
//  SwiftNZB
//
//  Root settings menu. Each category pushes a focused sub-screen with per-option explanations.
//

import SwiftUI

struct SettingsView: View {
    @State private var entitlements = Entitlements.shared
    @State private var purchases = PurchaseStore.shared

    var body: some View {
        List {
            Section {
                row("Servers", "Accounts and the default server", "server.rack") { ServersSettingsView() }
                row("Connections", "Parallel connections per download", "point.3.connected.trianglepath.dotted") { ConnectionsSettingsView() }
                row("Bandwidth", "Speed limit and cellular use", "speedometer") { BandwidthSettingsView() }
                row("Post-Processing", "PAR2 repair and RAR extraction", "wand.and.stars") { PostProcessingSettingsView() }
                row("Files & Storage", "Output location and free space", "folder") { StorageSettingsView() }
                row("Background", "Screen, notifications and background time", "bolt.badge.clock") { BackgroundSettingsView() }
            }
            Section {
                // Always here, whether or not there are free downloads left: this is where a
                // customer restores a purchase, and where App Review finds the purchases at all.
                row("SwiftNZB Pro", proSubtitle, "sparkles") { PaywallView() }
            }
            Section {
                row("About", nil, "info.circle") { AboutView() }
            }
            #if DEBUG
            if !AppRouter.isScreenshotRun {
                Section {
                    row("Entitlement (Debug)", nil, "ladybug") { EntitlementDebugView() }
                }
            }
            #endif
        }
        .navigationTitle("Settings")
    }

    private var proSubtitle: LocalizedStringKey {
        if entitlements.isPro {
            return purchases.isGrandfathered ? "Included, for good" : "Unlimited downloads"
        }
        return "^[\(entitlements.freeDownloadsRemaining) free download](inflect: true) left"
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
