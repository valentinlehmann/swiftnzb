//
//  StorageSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct StorageSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    private var available: Int64? { FileLocationService.shared.availableCapacityBytes() }

    var body: some View {
        Form {
            Section {
                Picker("Output layout", selection: $settingsStore.settings.folderMode) {
                    ForEach(FolderMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Completed Downloads")
            } footer: {
                Text("\"Subfolder per download\" keeps each download's files together; \"Single folder\" puts everything in one place. Completed downloads appear in the Files app under \"SwiftNZB\".")
            }

            Section("Device Storage") {
                if let available {
                    LabeledContent("Available") { Text(verbatim: Format.bytes(Int(available))) }
                }
            }
        }
        .navigationTitle("Files & Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}
