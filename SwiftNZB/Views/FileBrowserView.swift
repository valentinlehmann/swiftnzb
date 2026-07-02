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

    var body: some View {
        List {
            if contents.isEmpty {
                ContentUnavailableView("No Files", systemImage: "folder", description: Text("The output folder is empty."))
            } else {
                ForEach(contents, id: \.self) { url in
                    ShareLink(item: url) {
                        HStack {
                            Image(systemName: Self.icon(for: url))
                                .foregroundStyle(.secondary)
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
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// A recognizable SF Symbol for the file's type, so the list scans at a glance.
    private static func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mkv", "mp4", "avi", "mov", "m4v", "wmv", "flv", "webm": return "film"
        case "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff": return "photo"
        case "rar", "zip", "7z", "tar", "gz": return "doc.zipper"
        case "par2": return "checkmark.shield"
        case "iso", "img", "dmg": return "opticaldisc"
        case "pdf": return "doc.richtext"
        case "txt", "nfo", "srt", "sub": return "doc.text"
        default: return "doc"
        }
    }
}
