//
//  FileKind.swift
//  SwiftNZB
//

import SwiftUI

/// What role a file plays in a download: the payload the user actually came for, one volume of an
/// archive that has to be extracted first, or PAR2 recovery data. A 13-volume RAR set plus 8
/// recovery files buries the one file that matters, so the job detail groups by this.
enum FileKind: Sendable, Hashable, CaseIterable {
    case content
    case archivePart
    case parity

    var title: LocalizedStringKey {
        switch self {
        case .content: return "Content"
        case .archivePart: return "Archive Parts"
        case .parity: return "Recovery Data"
        }
    }

    var groupSystemImage: String {
        switch self {
        case .content: return "doc"
        case .archivePart: return "shippingbox"
        case .parity: return "checkmark.shield"
        }
    }

    /// Classify by extension. Covers `.par2`, single/multi-volume RAR (`.rar`, `.partNN.rar`), and
    /// old-style split volumes (`.r00`, `.001`).
    static func of(filename: String) -> FileKind {
        let lower = filename.lowercased()
        if lower.hasSuffix(".par2") { return .parity }
        if lower.hasSuffix(".rar") || lower.hasSuffix(".zip") || lower.hasSuffix(".7z") { return .archivePart }
        if let ext = lower.split(separator: ".").last, ext.count == 3 {
            if ext.first == "r", ext.dropFirst().allSatisfy(\.isNumber) { return .archivePart }
            if ext.allSatisfy(\.isNumber) { return .archivePart }
        }
        return .content
    }

    /// A recognizable SF Symbol for the file's own type, so a list of files scans at a glance.
    static func symbol(forFilename filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mkv", "mp4", "avi", "mov", "m4v", "wmv", "flv", "webm": return "film"
        case "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff": return "photo"
        case "epub", "mobi", "azw3", "cbz", "cbr": return "book"
        case "pdf": return "doc.richtext"
        case "iso", "img", "dmg": return "opticaldisc"
        case "txt", "nfo", "srt", "sub": return "doc.text"
        case "par2": return "checkmark.shield"
        case "rar", "zip", "7z", "tar", "gz": return "doc.zipper"
        default: return of(filename: filename) == .archivePart ? "doc.zipper" : "doc"
        }
    }
}
