import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Basılınca hafif küçülme; zemin ve renk görünümün kendisinde.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .notchAnimation(NotchMotion.press, value: configuration.isPressed)
    }
}

/// Sessiz metin düğmesi: yönetim ve ikincil eylemler. İkincil renkte; üzerine gelince aydınlanır.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration)
    }

    private struct QuietButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(NotchDesign.caption)
                .padding(.horizontal, NotchDesign.Space.s)
                .frame(height: NotchDesign.Control.small)
                .foregroundStyle(Color.white.opacity(isHovering ? 0.95 : 0.6))
                .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.small, style: .continuous)
                    .fill(configuration.isPressed ? NotchDesign.selectionFill : (isHovering ? NotchDesign.cardFill : .clear)))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : NotchDesign.disabledOpacity)
                .onHover { isHovering = $0 && isEnabled }
                .notchAnimation(NotchMotion.hover, value: isHovering)
        }
    }
}
