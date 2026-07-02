//
//  ArchiveExtractor.swift
//  SwiftNZB
//
//  Extracts downloaded RAR archives using the Unrar library, streaming each entry to disk so
//  large files never sit fully in memory. Picks the first volume of multi-volume sets; the
//  underlying UnRAR engine follows subsequent volumes (.partNN.rar / .rNN) in the same folder.
//

import Foundation
import Unrar

struct ArchiveExtractor {
    enum Outcome: Sendable, Equatable {
        case extracted(fileCount: Int)
        case noArchives
        case passwordRequired
        case failed(String)
    }

    /// Extract every RAR set found in `sourceDirectory` into `destinationDirectory`.
    static func extract(in sourceDirectory: URL, to destinationDirectory: URL, password: String? = nil) -> Outcome {
        let archives = firstVolumeArchives(in: sourceDirectory)
        guard !archives.isEmpty else { return .noArchives }

        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destRoot = destinationDirectory.standardizedFileURL
        var extractedCount = 0

        for archiveURL in archives {
            do {
                let archive = try Archive(fileURL: archiveURL, password: password)
                let entries = try archive.entries()
                for entry in entries where !entry.directory {
                    if entry.encrypted, password == nil { return .passwordRequired }

                    // Zip-slip guard: an archive entry name like "../../evil" would otherwise write
                    // outside the destination. Resolve the target and require it to stay inside.
                    guard let outURL = safeDestination(for: entry.fileName, under: destRoot) else {
                        return .failed("Archive contains an unsafe path: \(entry.fileName)")
                    }
                    try FileManager.default.createDirectory(
                        at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: outURL.path, contents: nil)
                    guard let handle = try? FileHandle(forWritingTo: outURL) else {
                        return .failed("Could not write \(entry.fileName)")
                    }
                    // Surface a write failure (e.g. disk full) instead of silently producing a
                    // truncated file that the caller then treats as a successful extraction.
                    var writeError: Error?
                    do {
                        try archive.extract(entry) { data, _ in
                            guard writeError == nil else { return }
                            do { try handle.write(contentsOf: data) } catch { writeError = error }
                        }
                    } catch {
                        try? handle.close()
                        return .failed("Extraction failed: \(error.localizedDescription)")
                    }
                    try? handle.close()
                    if let writeError {
                        return .failed("Could not write \(entry.fileName): \(writeError.localizedDescription)")
                    }
                    extractedCount += 1
                }
            } catch {
                return .failed("Extraction failed: \(error.localizedDescription)")
            }
        }
        return .extracted(fileCount: extractedCount)
    }

    /// Resolve an archive entry name to a URL guaranteed to live inside `root`, or nil if the entry
    /// tries to escape (absolute path, `..` traversal, etc.).
    static func safeDestination(for entryName: String, under root: URL) -> URL? {
        // Drop any leading slashes / drive-style prefix; take only the relative path components,
        // skipping "" and "." and rejecting ".." outright.
        let components = entryName.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var safe: [String] = []
        for component in components {
            if component == "." { continue }
            if component == ".." { return nil }
            safe.append(component)
        }
        guard !safe.isEmpty else { return nil }
        var url = root
        for component in safe { url.appendPathComponent(component) }
        // Belt-and-suspenders: the resolved path must still be within root.
        let resolved = url.standardizedFileURL.path
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved == root.path || resolved.hasPrefix(rootPath) else { return nil }
        return url
    }

    /// The first volume of each RAR set in a directory (skips `.partNN.rar` continuation volumes).
    static func firstVolumeArchives(in directory: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }

        return items
            .filter { $0.pathExtension.lowercased() == "rar" }
            .filter { isFirstVolume($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// True for a single-volume `.rar`, the new-style first volume `…part01.rar`, or an old-style
    /// `name.rar` (whose continuations are `.r00`, `.r01`, … and aren't `.rar` files).
    static func isFirstVolume(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".rar") else { return false }
        // New-style multi-volume: name.partNN.rar — only NN == 1 is the first volume.
        if let range = lower.range(of: #"\.part(\d+)\.rar$"#, options: .regularExpression) {
            let digits = lower[range].dropFirst(5).dropLast(4)   // strip ".part" and ".rar"
            return Int(digits) == 1
        }
        return true
    }
}
