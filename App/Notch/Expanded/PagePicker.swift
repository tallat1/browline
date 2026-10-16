import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Bölümün sayfa seçicisi: ince bir yuva içinde simge + ad bölütleri, seçili olanın zemini kayar.
/// Yalnız birden çok sayfası olan bölümde görünür.
struct PagePicker: View {
    let pages: [NotchTab]
    let selected: NotchTab
    let onHoverSegment: () -> Void
    let select: (NotchTab) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pages) { page in
                PageSegment(page: page, isSelected: page == selected, namespace: selection,
                            onHoverEnter: onHoverSegment) { select(page) }
            }
        }
        .padding(2)
        .background(Capsule().fill(NotchDesign.cardFill))
        .overlay(Capsule().strokeBorder(NotchDesign.hairline, lineWidth: 0.5))
        .frame(height: NotchDesign.Control.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchAnimation(NotchMotion.resize, value: selected)
    }
}

private struct PageSegment: View {
    let page: NotchTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let onHoverEnter: () -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: page.symbol)
                    .font(.system(size: 10, weight: NotchDesign.Icon.weight))
                Text(page.title).font(NotchDesign.captionEmphasized).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .foregroundStyle(Color.white.opacity(isSelected ? 1 : (isHovering ? 0.9 : 0.6)))
            .background {
                if isSelected {
                    Capsule().fill(NotchDesign.selectionFill).matchedGeometryEffect(id: "page", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            if inside, !isHovering { onHoverEnter() }
            isHovering = inside
        }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(page.title)
    }
}
