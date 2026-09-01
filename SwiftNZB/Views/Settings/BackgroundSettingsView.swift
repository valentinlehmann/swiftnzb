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
                Toggle("Keep Screen Awake", isOn: $settingsStore.settings.keepScreenAwakeWhileDownloading)
                    .onChange(of: settingsStore.settings.keepScreenAwakeWhileDownloading) {
                        DownloadManager.shared.refreshIdleTimer()
                    }
            } footer: {
                Text("The screen stays on while a download runs. iOS drops the Usenet connections as soon as the app leaves the foreground, and locking the screen does exactly that, so a download stops shortly after the screen goes dark.")
            }

            Section {
                Toggle("Notify When a Download Ends", isOn: $settingsStore.settings.notifyOnFinish)
            } footer: {
                Text("Sends a notification when a download finishes or fails while you are somewhere else. Nothing is sent while SwiftNZB is on screen.")
            }

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
