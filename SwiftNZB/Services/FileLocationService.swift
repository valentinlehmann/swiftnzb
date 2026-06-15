//
//  FileLocationService.swift
//  SwiftNZB
//
//  Resolves the on-disk folders the app uses. Everything lives under the app's Documents
//  container so completed downloads are visible in the Files app (UIFileSharingEnabled +
//  LSSupportsOpeningDocumentsInPlace).
//

import Foundation

struct FileLocationService {
    static let shared = FileLocationService()

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// In-progress scratch (sparse `.part` files + checkpoints), one subfolder per job.
    var incompleteFolder: URL { documents.appendingPathComponent("incomplete", isDirectory: true) }

    /// Finished output, visible to the user in Files.
    var completeFolder: URL { documents.appendingPathComponent("complete", isDirectory: true) }

    /// Imported `.nzb` files we keep for re-queue / resume.
    var nzbFolder: URL { documents.appendingPathComponent("nzb", isDirectory: true) }

    /// Engine working directory for a job (scratch files + checkpoint).
    func workingDirectory(forJobID id: UUID) -> URL {
        incompleteFolder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Destination folder for a completed job, honoring the folder-mode preference.
    func completedDirectory(for job: DownloadJob, mode: FolderMode) -> URL {
        switch mode {
        case .flat: return completeFolder
        case .perJobSubfolder:
            return completeFolder.appendingPathComponent(sanitized(job.name), isDirectory: true)
        }
    }

    func ensureBaseFolders() {
        for url in [incompleteFolder, completeFolder, nzbFolder] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    @discardableResult
    func ensureDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func removeWorkingDirectory(forJobID id: UUID) {
        try? FileManager.default.removeItem(at: workingDirectory(forJobID: id))
    }

    func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Download" : cleaned
    }
}
