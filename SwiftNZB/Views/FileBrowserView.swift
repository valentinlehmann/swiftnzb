//
//  FileBrowserView.swift
//  SwiftNZB
//
//  Lists a completed job's output files (which also live in the Files app under "SwiftNZB")
//  and lets the user share/export each one.
//

import SwiftUI

struct FileBrowserView: View {
    let job: DownloadJob
    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroups: Set<FileKind> = []

    private var folder: URL {
        if let relative = job.completedFolderRelativePath {
            return FileLocationService.shared.completeFolder.appendingPathComponent(relative, isDirectory: true)
        }
        return FileLocationService.shared.completedDirectory(for: job, mode: SettingsStore.shared.settings.folderMode)
    }

    private var contents: [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// Same split as the job detail: what the download was for, then the volumes and parity that
    /// produced it, collapsed out of the way.
    private var grouped: [FileKind: [URL]] {
        Dictionary(grouping: contents) { FileKind.of(filename: $0.lastPathComponent) }
    }

    var body: some View {
        List {
            if contents.isEmpty {
                ContentUnavailableView("No Files", systemImage: "folder", description: Text("The output folder is empty."))
            } else {
                let byKind = grouped
                if let content = byKind[.content], !content.isEmpty {
                    Section(FileKind.content.title) {
                        ForEach(content, id: \.self) { row($0) }
                    }
                }
                ForEach([FileKind.archivePart, .parity], id: \.self) { kind in
                    if let files = byKind[kind], !files.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: expansion(kind)) {
                                ForEach(files, id: \.self) { row($0) }
                            } label: {
                                FileKindGroupLabel(kind: kind, count: files.count)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func row(_ url: URL) -> some View {
        ShareLink(item: url) {
            HStack {
                Image(systemName: FileKind.symbol(forFilename: url.lastPathComponent))
                    .foregroundStyle(FileKind.of(filename: url.lastPathComponent) == .content ? .primary : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).lineLimit(1)
                    Text(verbatim: Format.bytes(fileSize(url)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
            }
        }
    }

    private func expansion(_ kind: FileKind) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(kind) },
            set: { expanded in
                if expanded { expandedGroups.insert(kind) } else { expandedGroups.remove(kind) }
            }
        )
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
