//
//  StatRow.swift
//  SwiftNZB
//
//  One labeled metric as a plain list row. Values go through `Text(verbatim:)` to keep byte
//  counts, speeds and connection counts free of a locale thousands separator, and tick over as
//  digits rather than snapping.
//

import SwiftUI

struct StatRow: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent(title) {
            Text(verbatim: value)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: value)
        }
    }
}
