//
//  CircleActionButton.swift
//  SwiftNZB
//
//  Icon-only round control. Uses a fixed tinted circle for sizing (NOT frame+padding), since
//  prominent glass button styles add their own padding.
//

import SwiftUI

struct CircleActionButton: View {
    let systemImage: String
    var tint: Color = .accentColor
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: Circle())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
