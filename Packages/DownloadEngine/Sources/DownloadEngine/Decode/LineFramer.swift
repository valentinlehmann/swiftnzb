//
//  LineFramer.swift
//  DownloadEngine
//
//  Incrementally splits a byte stream into lines. NNTP is line-oriented and CRLF-terminated;
//  this buffers partial reads and yields complete lines (with the trailing CRLF/LF removed).
//

import Foundation

struct LineFramer {
    private var buffer = Data()

    /// Append freshly-read bytes and return every complete line now available.
    /// A trailing partial line (no terminator yet) stays buffered for the next append.
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        return drainCompleteLines()
    }

    /// Any bytes buffered that haven't been terminated by a newline yet.
    var pending: Data { buffer }

    private mutating func drainCompleteLines() -> [Data] {
        var lines: [Data] = []
        let lf: UInt8 = 0x0A
        let cr: UInt8 = 0x0D

        while let lfIndex = buffer.firstIndex(of: lf) {
            // Line content is everything before the LF, minus a preceding CR if present.
            var end = lfIndex
            if end > buffer.startIndex, buffer[buffer.index(before: end)] == cr {
                end = buffer.index(before: end)
            }
            let line = buffer[buffer.startIndex..<end]
            lines.append(Data(line))
            // Advance past the LF.
            buffer = Data(buffer[buffer.index(after: lfIndex)...])
        }
        return lines
    }
}
