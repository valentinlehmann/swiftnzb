//
//  FileAssembler.swift
//  DownloadEngine
//
//  Writes decoded segment bytes straight to disk at their authoritative byte offset (from the
//  yEnc =ypart header), into one sparse `.part` scratch file per NZB file. The scratch file IS
//  the assembled output — finalize just renames it. Positional writes at fixed offsets make the
//  whole thing idempotent and therefore resume-safe.
//
//  An actor: disk writes are serialized (the network, not the disk, is the bottleneck), which
//  trades a little throughput for guaranteed correctness over many concurrent workers.
//

import Foundation

actor FileAssembler {
    private let directory: URL
    private var handles: [String: FileHandle] = [:]   // fileID → open handle on its .part file
    private var urls: [String: URL] = [:]             // fileID → .part URL
    private var finalNames: [String: String] = [:]    // fileID → final filename

    init(directory: URL) {
        self.directory = directory
    }

    /// Create (or reopen) the scratch file for a file, sized to `totalBytes` so missing regions
    /// stay zero-filled for PAR2 to repair. Idempotent — safe to call on resume.
    func prepare(fileID: String, filename: String, totalBytes: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partURL = directory.appendingPathComponent(sanitized(filename) + ".part")
        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partURL)
        if totalBytes > 0 { try handle.truncate(atOffset: UInt64(totalBytes)) }
        handles[fileID] = handle
        urls[fileID] = partURL
        finalNames[fileID] = sanitized(filename)
        excludeFromBackup(partURL)
    }

    func write(fileID: String, data: Data, at offset: Int) throws {
        guard let handle = handles[fileID] else { return }
        try handle.seek(toOffset: UInt64(max(0, offset)))
        try handle.write(contentsOf: data)
    }

    /// Close and rename the scratch file to its final name. Returns the final URL.
    @discardableResult
    func finalize(fileID: String) throws -> URL? {
        guard let partURL = urls[fileID] else { return nil }
        try? handles[fileID]?.synchronize()
        try? handles[fileID]?.close()
        handles[fileID] = nil

        let finalURL = directory.appendingPathComponent(finalNames[fileID] ?? partURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: partURL, to: finalURL)
        urls[fileID] = finalURL
        excludeFromBackup(finalURL)
        return finalURL
    }

    func closeAll() {
        for handle in handles.values { try? handle.close() }
        handles.removeAll()
    }

    // MARK: - Helpers

    private func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "_")
        return cleaned.isEmpty ? "file" : cleaned
    }

    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
