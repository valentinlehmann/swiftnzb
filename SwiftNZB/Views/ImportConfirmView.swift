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

    private let lowSpaceThreshold: Int64 = 500 * 1024 * 1024   // 500 MB headroom

    private var availableBytes: Int64? { FileLocationService.shared.availableCapacityBytes() }
    private var freeAfterBytes: Int64? { availableBytes.map { $0 - Int64(job.totalBytes) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Download") {
                    TextField("Name", text: $name)
                    LabeledContent("Files") { Text(verbatim: "\(job.files.count)") }
                    LabeledContent("Total size") { Text(verbatim: Format.bytes(job.totalBytes)) }
                }

                if let available = availableBytes {
                    Section {
                        LabeledContent("Available") { Text(verbatim: Format.bytes(Int(available))) }
                        LabeledContent("Free after download") {
                            Text(verbatim: Format.bytes(Int(max(0, freeAfterBytes ?? 0))))
                                .foregroundStyle((freeAfterBytes ?? 0) < lowSpaceThreshold ? Color.red : Color.secondary)
                        }
                        if (freeAfterBytes ?? 0) < 0 {
                            Label("This download is larger than the free space available.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.red)
                        } else if (freeAfterBytes ?? 0) < lowSpaceThreshold {
                            Label("Low on space — extraction needs extra room, so leave some headroom.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Storage")
                    } footer: {
                        Text("Extraction temporarily needs extra space beyond the download size.")
                    }
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
