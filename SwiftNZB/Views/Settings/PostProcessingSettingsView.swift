//
//  PostProcessingSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct PostProcessingSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    /// One switch for the whole PAR2 feature — verify implies the ability to repair. (The label
    /// previously bound only to the repair flag, so verification could never be turned off.)
    private var par2Enabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.par2VerifyEnabled },
            set: {
                settingsStore.settings.par2VerifyEnabled = $0
                settingsStore.settings.par2RepairEnabled = $0
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Verify & Repair with PAR2", isOn: par2Enabled)
            } footer: {
                Text("PAR2 recovery files find damaged and missing pieces and rebuild them, so a download with holes in it can still finish intact.")
            }

            Section {
                Toggle("Extract RAR Archives", isOn: $settingsStore.settings.unrarEnabled)
                Toggle("Delete Archives After Extraction", isOn: $settingsStore.settings.deleteArchivesAfterExtract)
                    .disabled(!settingsStore.settings.unrarEnabled)
            } footer: {
                Text("Posts usually arrive as a set of RAR volumes. SwiftNZB unpacks them into the completed folder, and deletes the volumes afterwards if you let it.")
            }
        }
        .navigationTitle("Post-Processing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
