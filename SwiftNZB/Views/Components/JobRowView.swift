//
//  JobRowView.swift
//  SwiftNZB
//

import SwiftUI

/// One row in the queue: name, progress, live speed/ETA, status.
struct JobRowView: View {
    let job: DownloadJob
    /// Live speed for the active job (0 for others).
    var bytesPerSecond: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusChip(status: job.status)
            }

            ProgressView(value: job.progress)
                .tint(job.status.tint)

            HStack {
                Text(verbatim: "\(Format.bytes(job.downloadedBytes)) / \(Format.bytes(job.totalBytes))")
                Spacer()
                if job.status == .downloading, bytesPerSecond > 0 {
                    Text(verbatim: Format.speed(bytesPerSecond))
                    if let eta = Format.eta(remainingBytes: max(0, job.totalBytes - job.downloadedBytes),
                                            bytesPerSecond: bytesPerSecond) {
                        Text(verbatim: "· \(eta)")
                    }
                } else {
                    Text(verbatim: Format.percent(job.progress))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
