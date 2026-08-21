//
//  ConnectionsSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct ConnectionsSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Stepper(value: $settingsStore.settings.maxGlobalConnections, in: 1...100) {
                    LabeledContent("Max Connections") {
                        Text(verbatim: "\(settingsStore.settings.maxGlobalConnections)")
                    }
                }
            } footer: {
                Text("How many articles download at once. More is faster, up to the limit your Usenet plan allows. Past that, the provider starts refusing connections.")
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }
}
