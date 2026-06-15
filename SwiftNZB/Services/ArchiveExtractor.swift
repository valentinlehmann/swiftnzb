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
        var extractedCount = 0

        for archiveURL in archives {
            do {
                let archive = try Archive(fileURL: archiveURL, password: password)
                let entries = try archive.entries()
                for entry in entries where !entry.directory {
                    if entry.encrypted, password == nil { return .passwordRequired }
                    let outURL = destinationDirectory.appendingPathComponent(entry.fileName)
                    try FileManager.default.createDirectory(
                        at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: outURL.path, contents: nil)
                    guard let handle = try? FileHandle(forWritingTo: outURL) else {
                        return .failed("Could not write \(entry.fileName)")
                    }
                    defer { try? handle.close() }
                    try archive.extract(entry) { data, _ in
                        try? handle.write(contentsOf: data)
                    }
                    extractedCount += 1
                }
            } catch {
                return .failed("Extraction failed: \(error.localizedDescription)")
            }
        }
        return .extracted(fileCount: extractedCount)
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
