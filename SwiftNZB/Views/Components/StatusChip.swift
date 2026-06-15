//
//  StatusChip.swift
//  SwiftNZB
//

import SwiftUI

/// A small colored capsule showing a job's status.
struct StatusChip: View {
    let status: JobStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
    }
}
