//
//  BandwidthSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct BandwidthSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    private var speedLimitEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.bandwidthCapKBps > 0 },
            set: { settingsStore.settings.bandwidthCapKBps = $0 ? max(settingsStore.settings.bandwidthCapKBps, 5 * 1024) : 0 }
        )
    }

    private var speedLimitMBps: Binding<Int> {
        Binding(
            get: { max(1, settingsStore.settings.bandwidthCapKBps / 1024) },
            set: { settingsStore.settings.bandwidthCapKBps = $0 * 1024 }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Limit download speed", isOn: speedLimitEnabled)
                if settingsStore.settings.bandwidthCapKBps > 0 {
                    Stepper(value: speedLimitMBps, in: 1...100) {
                        LabeledContent("Speed limit") { Text(verbatim: "\(speedLimitMBps.wrappedValue) MB/s") }
                    }
                }
            } header: {
                Text("Speed Limit")
            } footer: {
                Text("Caps the total download speed across all connections — handy on shared or metered links. Off means download as fast as the connections allow.")
            }

            Section {
                Toggle("Pause on cellular", isOn: $settingsStore.settings.pauseOnCellular)
            } footer: {
                Text("When on, downloads pause while you're on a cellular connection and resume automatically on Wi-Fi.")
            }
        }
        .navigationTitle("Bandwidth")
        .navigationBarTitleDisplayMode(.inline)
    }
}
