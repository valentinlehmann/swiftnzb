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
    @State private var selected: Set<UUID>

    init(job: DownloadJob) {
        self.job = job
        _name = State(initialValue: job.name)
        _serverID = State(initialValue: Self.initialServerID())
        _selected = State(initialValue: Set(job.files.map(\.id)))   // all selected by default
    }

    private let lowSpaceThreshold: Int64 = 500 * 1024 * 1024   // 500 MB headroom

    private var selectedFiles: [NZBFileSummary] { job.files.filter { selected.contains($0.id) } }
    private var selectedTotalBytes: Int { selectedFiles.reduce(0) { $0 + $1.totalBytes } }
    private var availableBytes: Int64? { FileLocationService.shared.availableCapacityBytes() }
    private var freeAfterBytes: Int64? { availableBytes.map { $0 - Int64(selectedTotalBytes) } }
    private var allSelected: Bool { selected.count == job.files.count }

    var body: some View {
        NavigationStack {
            Form {
                Section("Download") {
                    TextField("Name", text: $name)
                }

                Section {
                    LabeledContent("Total size") { Text(verbatim: Format.bytes(selectedTotalBytes)) }
                    if let available = availableBytes {
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
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Extraction temporarily needs extra space beyond the download size.")
                }

                Section("Server") {
                    Picker("Server", selection: $serverID) {
                        Text("Default").tag(UUID?.none)
                        ForEach(servers.accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }

                Section {
                    ForEach(job.files) { file in
                        Button {
                            if selected.contains(file.id) { selected.remove(file.id) } else { selected.insert(file.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(file.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.filename).lineLimit(1)
                                    Text(verbatim: Format.bytes(file.totalBytes))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(verbatim: "Files (\(selected.count)/\(job.files.count))")
                        Spacer()
                        Button(allSelected ? "Deselect All" : "Select All") {
                            selected = allSelected ? [] : Set(job.files.map(\.id))
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
            .navigationTitle("Add to Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        ImportCoordinator.shared.confirm(name: name, serverID: serverID, selectedFileIDs: selected)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
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

    /// Preselect the saved default server (if it still exists), else the primary account.
    private static func initialServerID() -> UUID? {
        let settings = SettingsStore.shared.settings
        if let id = settings.defaultServerID, ServerStore.shared.account(id) != nil { return id }
        return ServerStore.shared.primaryServer?.id
    }
}
