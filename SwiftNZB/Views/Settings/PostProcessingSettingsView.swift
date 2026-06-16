//
//  PostProcessingSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct PostProcessingSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Verify & repair with PAR2", isOn: $settingsStore.settings.par2RepairEnabled)
            } footer: {
                Text("PAR2 recovery files detect damaged or missing pieces after a download and rebuild them, so an incomplete download can still finish intact.")
            }

            Section {
                Toggle("Extract RAR archives", isOn: $settingsStore.settings.unrarEnabled)
                Toggle("Delete archives after extraction", isOn: $settingsStore.settings.deleteArchivesAfterExtract)
                    .disabled(!settingsStore.settings.unrarEnabled)
            } footer: {
                Text("Most Usenet posts are split RAR archives. When enabled, SwiftNZB unpacks them into the completed folder and (optionally) removes the now-redundant archive parts to save space.")
            }
        }
        .navigationTitle("Post-Processing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
