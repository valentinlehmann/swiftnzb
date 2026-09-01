//
//  StorageSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct StorageSettingsView: View {
    @Bindable private var settingsStore = SettingsStore.shared

    private var available: Int64? { FileLocationService.shared.availableCapacityBytes() }

    /// 0 means keep everything, matching `DownloadSettings.keepCompletedHistoryDays`.
    private static let retentionChoices = [7, 30, 90, 0]

    private static func retentionLabel(_ days: Int) -> LocalizedStringKey {
        switch days {
        case 7: return "1 Week"
        case 30: return "1 Month"
        case 90: return "3 Months"
        default: return "Forever"
        }
    }

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
                Picker("Keep Finished Downloads", selection: $settingsStore.settings.keepCompletedHistoryDays) {
                    ForEach(Self.retentionChoices, id: \.self) { days in
                        Text(Self.retentionLabel(days)).tag(days)
                    }
                }
                .onChange(of: settingsStore.settings.keepCompletedHistoryDays) {
                    DownloadManager.shared.applyHistoryRetention()
                }
            } header: {
                Text("Downloads List")
            } footer: {
                Text("How long a finished download stays in the list. Removing an entry also discards whatever a failed download left half-finished. Files that made it to the Files app are never touched.")
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
