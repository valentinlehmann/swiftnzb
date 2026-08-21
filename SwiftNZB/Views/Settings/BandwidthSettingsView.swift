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
            set: { settingsStore.settings.bandwidthCapKBps = max(1, $0) * 1024 }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Limit Download Speed", isOn: speedLimitEnabled)
                if settingsStore.settings.bandwidthCapKBps > 0 {
                    LabeledContent("Speed Limit") {
                        HStack(spacing: 6) {
                            TextField("0", value: speedLimitMBps, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                            Text("MB/s").foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Speed Limit")
            } footer: {
                Text("Caps the combined speed of every connection. Off means SwiftNZB downloads as fast as the server allows.")
            }

            Section {
                Toggle("Pause on Cellular", isOn: $settingsStore.settings.pauseOnCellular)
            } footer: {
                Text("Downloads pause on cellular and in Low Data Mode, then resume once you are back on Wi-Fi.")
            }
        }
        .navigationTitle("Bandwidth")
        .navigationBarTitleDisplayMode(.inline)
    }
}
