//
//  SettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct SettingsView: View {
    @State private var servers = ServerStore.shared
    @Bindable private var settingsStore = SettingsStore.shared

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section("Servers") {
                ForEach(servers.accounts) { account in
                    NavigationLink {
                        AddServerView(existing: account)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(verbatim: "\(account.host):\(account.port)\(account.useSSL ? " · SSL" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { servers.remove(account.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                NavigationLink {
                    AddServerView()
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            }

            Section("Connections") {
                Stepper(value: $settingsStore.settings.maxGlobalConnections, in: 1...100) {
                    LabeledContent("Max connections") {
                        Text(verbatim: "\(settingsStore.settings.maxGlobalConnections)")
                    }
                }
            }

            Section {
                Toggle("Verify & repair with PAR2", isOn: $settingsStore.settings.par2RepairEnabled)
                Toggle("Extract RAR archives", isOn: $settingsStore.settings.unrarEnabled)
                Toggle("Delete archives after extraction", isOn: $settingsStore.settings.deleteArchivesAfterExtract)
                    .disabled(!settingsStore.settings.unrarEnabled)
            } header: {
                Text("Post-Processing")
            } footer: {
                Text("After downloading, SwiftNZB verifies (and repairs) files using PAR2 recovery data, then extracts RAR archives into the completed folder.")
            }

            Section("Folders") {
                Picker("Output layout", selection: $settingsStore.settings.folderMode) {
                    ForEach(FolderMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section {
                Toggle("Pause on cellular", isOn: $settingsStore.settings.pauseOnCellular)
            } header: {
                Text("Network")
            } footer: {
                Text("Large downloads need the app open — iOS can't run Usenet downloads unattended in the background. The app makes opportunistic progress when possible and resumes where it left off.")
            }

            Section("About") {
                LabeledContent("Version") { Text(verbatim: appVersion) }
            }
        }
        .navigationTitle("Settings")
    }
}
