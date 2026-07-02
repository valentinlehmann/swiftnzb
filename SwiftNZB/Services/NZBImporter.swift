//
//  NZBImporter.swift
//  SwiftNZB
//
//  Parses an `.nzb` (XML) file into a `DownloadJob`. Pure parsing — no networking.
//

import Foundation

enum NZBImportError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The NZB file could not be read."
        case .empty: return "The NZB file contains no downloadable files."
        }
    }
}

struct NZBImporter {
    static let shared = NZBImporter()

    /// Read + parse an NZB at `url` (security-scoped), copy it into the app's nzb folder, and
    /// build a queued `DownloadJob`.
    func importNZB(at url: URL) throws -> DownloadJob {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw NZBImportError.unreadable }

        FileLocationService.shared.ensureBaseFolders()
        // Keep a copy under a unique name so re-importing a file with the same name doesn't clobber
        // an earlier one.
        let base = FileLocationService.shared.sanitized(url.deletingPathExtension().lastPathComponent)
        let savedURL = FileLocationService.shared.nzbFolder
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(8)).nzb")
        try? data.write(to: savedURL, options: .atomic)

        let parsed = NZBParser.parse(data: data)
        guard !parsed.files.isEmpty else {
            // Empty either because the file isn't a valid NZB or it genuinely lists no files.
            throw parsed.parseFailed ? NZBImportError.unreadable : NZBImportError.empty
        }

        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = parsed.title?.isEmpty == false ? parsed.title! : fallbackName
        return DownloadJob(name: name, files: parsed.files)
    }
}

// MARK: - XML parsing

struct ParsedNZB {
    var title: String?
    var files: [NZBFileSummary]
    /// True if the XML was malformed (as opposed to well-formed but listing no files).
    var parseFailed: Bool = false
}

private final class NZBParser: NSObject, XMLParserDelegate {
    private var files: [NZBFileSummary] = []
    private var title: String?
    private var parseFailed = false

    // Current <file>
    private var currentSubject: String?
    private var currentGroups: [String] = []
    private var currentSegments: [NZBSegmentSummary] = []

    // Current <segment>
    private var currentSegmentBytes = 0
    private var currentSegmentNumber = 0
    private var textBuffer = ""
    private var currentMetaType: String?

    static func parse(data: Data) -> ParsedNZB {
        let parser = NZBParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        let ok = xml.parse()
        // Treat a fatal XML error with nothing recovered as a malformed file (so the user gets a
        // clear "couldn't read" rather than a silent, truncated import).
        let failed = (!ok || parser.parseFailed) && parser.files.isEmpty
        return ParsedNZB(title: parser.title, files: parser.files, parseFailed: failed)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parseFailed = true
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        textBuffer = ""
        switch elementName {
        case "file":
            currentSubject = attributeDict["subject"]
            currentGroups = []
            currentSegments = []
        case "segment":
            currentSegmentBytes = Int(attributeDict["bytes"] ?? "") ?? 0
            currentSegmentNumber = Int(attributeDict["number"] ?? "") ?? (currentSegments.count + 1)
        case "meta":
            currentMetaType = attributeDict["type"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "group":
            if !text.isEmpty { currentGroups.append(text) }
        case "segment":
            let messageID = text.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            if !messageID.isEmpty {
                currentSegments.append(NZBSegmentSummary(
                    messageID: messageID, byteCount: currentSegmentBytes, number: currentSegmentNumber))
            }
        case "meta":
            if currentMetaType == "title", !text.isEmpty { title = text }
            currentMetaType = nil
        case "file":
            let subject = currentSubject ?? ""
            let filename = Self.filename(fromSubject: subject, fallback: "file\(files.count + 1)")
            if !currentSegments.isEmpty {
                files.append(NZBFileSummary(
                    subject: subject,
                    filename: filename,
                    groups: currentGroups,
                    segments: currentSegments.sorted { $0.number < $1.number }))
            }
            currentSubject = nil
        default:
            break
        }
        textBuffer = ""
    }

    /// Best-effort filename extraction: the bit inside the first pair of double quotes in the
    /// subject (the Usenet convention), else a cleaned token, else the fallback.
    static func filename(fromSubject subject: String, fallback: String) -> String {
        if let open = subject.firstIndex(of: "\""),
           let close = subject[subject.index(after: open)...].firstIndex(of: "\"") {
            let name = String(subject[subject.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        // Fallback: a token that looks like a filename (has an extension).
        for token in subject.split(whereSeparator: { $0 == " " || $0 == "\"" }) {
            if token.contains("."), !token.hasPrefix("(") { return String(token) }
        }
        return fallback
    }
}
