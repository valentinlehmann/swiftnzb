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
                    LabeledContent("Max connections") {
                        Text(verbatim: "\(settingsStore.settings.maxGlobalConnections)")
                    }
                }
            } footer: {
                Text("How many article downloads run in parallel. More connections download faster, but never exceed the limit your Usenet plan allows or the provider may refuse them.")
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }
}
