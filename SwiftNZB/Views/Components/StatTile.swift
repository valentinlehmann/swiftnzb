//
//  StatTile.swift
//  SwiftNZB
//
//  Compact labeled metric card (icon + value + caption). Values use `Text(verbatim:)` to keep
//  byte counts / speeds / counts free of locale thousands separators.
//

import SwiftUI

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage: String?
    var tint: Color = .primary

    init(_ title: LocalizedStringKey, _ value: String, systemImage: String? = nil, tint: Color = .primary) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            Text(verbatim: value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
