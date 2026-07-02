//
//  JobRowView.swift
//  SwiftNZB
//

import SwiftUI

/// One row in the queue: name, progress, live speed/ETA (or post-processing step), status.
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
                .animation(.default, value: job.progress)

            HStack {
                Text(verbatim: "\(Format.bytes(job.downloadedBytes)) / \(Format.bytes(job.totalBytes))")
                Spacer()
                trailingDetail
                    .contentTransition(.numericText())
                    .animation(.default, value: bytesPerSecond)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var trailingDetail: some View {
        if let step = job.currentStep {
            Text(step.title)   // Verifying / Repairing / Extracting …
        } else if job.status == .downloading, bytesPerSecond > 0 {
            let remaining = max(0, job.totalBytes - job.downloadedBytes)
            if let eta = Format.eta(remainingBytes: remaining, bytesPerSecond: bytesPerSecond) {
                Text(verbatim: "\(Format.speed(bytesPerSecond)) · \(eta)")
            } else {
                Text(verbatim: Format.speed(bytesPerSecond))
            }
        } else {
            Text(verbatim: Format.percent(job.progress))
        }
    }
}
