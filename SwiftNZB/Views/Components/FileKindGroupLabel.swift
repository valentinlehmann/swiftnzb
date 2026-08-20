//
//  FileKindGroupLabel.swift
//  SwiftNZB
//
//  Header for a collapsed group of archive volumes / recovery files: role on the left, how many on
//  the right. Shared so the job detail and the output browser group files the same way.
//

import SwiftUI

struct FileKindGroupLabel: View {
    let kind: FileKind
    let count: Int

    var body: some View {
        HStack {
            Label(kind.title, systemImage: kind.groupSystemImage)
                .font(.subheadline)
            Spacer()
            // Text("\(count)") would pick up a locale thousands separator.
            Text(verbatim: "\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
