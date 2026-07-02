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
                Image(systemName: file.isPar2 ? "checkmark.shield" : "doc")
                    .foregroundStyle(.secondary)
                Text(file.filename)
                    .font(.subheadline)
                    .lineLimit(1)
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
