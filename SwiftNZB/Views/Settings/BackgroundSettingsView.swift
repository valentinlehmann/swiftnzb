//
//  BackgroundSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct BackgroundSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Only When Charging", isOn: $settingsStore.settings.requireExternalPowerForBackground)
            } footer: {
                Text("Background resume only runs while the device is charging. Turn this off to let it run on battery too.")
            }

            Section {
                Text("iOS won't keep a Usenet connection alive in the background, so large downloads need the app open. When you leave, SwiftNZB finishes the article it is on and saves its place. It resumes when iOS next gives it time to run, or as soon as you reopen the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How background downloading works")
            }
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
    }
}
