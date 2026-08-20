//
//  FileProgressRow.swift
//  SwiftNZB
//

import SwiftUI

struct FileProgressRow: View {
    let file: NZBFileSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: FileKind.symbol(forFilename: file.filename))
                    .foregroundStyle(file.kind == .content ? .primary : .secondary)
                // Middle truncation so the file type stays readable on a long name.
                Text(file.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(verbatim: Format.percent(file.progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: file.progress)
            HStack(spacing: 4) {
                Text(verbatim: "\(Format.bytes(file.downloadedBytes)) / \(Format.bytes(file.totalBytes))")
                if !file.segments.isEmpty {
                    Text(verbatim: "·")
                    Text("\(file.segments.count) segments")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
