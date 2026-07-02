//
//  CircleActionButton.swift
//  SwiftNZB
//
//  Icon-only round control. A fixed glyph frame defines the tappable area (≥44pt) while the glass
//  button style provides its own padding and the circular border shape.
//

import SwiftUI

struct CircleActionButton: View {
    let systemImage: String
    /// VoiceOver label — required because the button shows only an icon.
    let label: LocalizedStringKey
    var tint: Color = .accentColor
    var prominent: Bool = false
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonBorderShape(.circle)
        .tint(tint)
        .modifier(GlassStyle(prominent: prominent))
        .accessibilityLabel(label)
    }
}

/// Applies `.glassProminent` for a primary action, `.glass` otherwise.
private struct GlassStyle: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}
