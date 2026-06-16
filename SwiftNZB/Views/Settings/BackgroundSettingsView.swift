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
                Toggle("Only when charging", isOn: $settingsStore.settings.requireExternalPowerForBackground)
            } footer: {
                Text("Limits opportunistic background resume to when the device is plugged in, to save battery.")
            }

            Section {
                Text("iOS can't keep Usenet downloads running unattended in the background — large downloads need the app open. When you leave the app, SwiftNZB finishes the current piece, saves its place, and resumes automatically next time it gets a moment to run or when you reopen it.")
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
