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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Download") {
                    TextField("Name", text: $name)
                    LabeledContent("Files") { Text(verbatim: "\(job.files.count)") }
                    LabeledContent("Total size") { Text(verbatim: Format.bytes(job.totalBytes)) }
                }
                Section("Server") {
                    Picker("Server", selection: $serverID) {
                        Text("Default").tag(UUID?.none)
                        ForEach(servers.accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
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
