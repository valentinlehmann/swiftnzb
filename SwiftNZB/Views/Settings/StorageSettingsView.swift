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
                Picker("Output Layout", selection: $settingsStore.settings.folderMode) {
                    ForEach(FolderMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Completed Downloads")
            } footer: {
                Text("\"Subfolder per download\" keeps each download's files together. \"Single folder\" puts everything in one place. Either way, the files show up in the Files app under \"SwiftNZB\".")
            }

            Section {
                Toggle("Choose Files on Import", isOn: $settingsStore.settings.fileSelectionOnImport)
            } header: {
                Text("Expert")
            } footer: {
                Text("Shows the file list when you add an NZB, so you can leave parts out. Repair and extraction need every volume and PAR2 file a post carries, so a partial pick usually produces a download you can't open.")
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
