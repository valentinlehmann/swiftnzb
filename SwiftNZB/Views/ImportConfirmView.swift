//
//  ImportConfirmView.swift
//  SwiftNZB
//

import SwiftUI

struct ImportConfirmView: View {
    let job: DownloadJob

    @Environment(\.dismiss) private var dismiss
    @State private var servers = ServerStore.shared
    @State private var name: String
    @State private var serverID: UUID?

    init(job: DownloadJob) {
        self.job = job
        _name = State(initialValue: job.name)
        _serverID = State(initialValue: Self.initialServerID())
    }

    /// Preselect the saved default server (if it still exists), else the primary account.
    private static func initialServerID() -> UUID? {
        let settings = SettingsStore.shared.settings
        if let id = settings.defaultServerID, ServerStore.shared.account(id) != nil { return id }
        return ServerStore.shared.primaryServer?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Download") {
                    TextField("Name", text: $name)
                    LabeledContent("Files") { Text(verbatim: "\(job.files.count)") }
                    LabeledContent("Total size") { Text(verbatim: Format.bytes(job.totalBytes)) }
                }
                Section {
                    Picker("Server", selection: $serverID) {
                        ForEach(servers.accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Your choice is remembered as the default for next time.")
                }
            }
            .navigationTitle("Add to Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        ImportCoordinator.shared.confirm(name: name, serverID: serverID)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ImportCoordinator.shared.clear()
                        dismiss()
                    }
                }
            }
        }
    }
}
