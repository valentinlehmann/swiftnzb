//
//  CheckboxView.swift
//  SwiftNZB
//
//  Shared selection checkbox, styled to match the History list's selection mark exactly.
//  Used by both the Add to Queue file list and History so they look identical, with a subtle
//  symbol replace + bounce on check/uncheck.
//

import SwiftUI

struct CheckboxView: View {
    let isChecked: Bool

    var body: some View {
        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isChecked)
    }
}
