import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Bantta beş bölüm simgesi (yalnız simge; ad üzerine gelince). Seçili olan tam beyaz ve zeminli,
/// diğerleri soluk, üzerine gelince aydınlanır. Seçim kayan bir zeminle geçer.
struct SectionBar: View {
    let sections: [NotchSection]
    let selected: NotchSection
    let onHoverIcon: () -> Void
    let select: (NotchSection) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: NotchDesign.sectionIconSpacing) {
            ForEach(sections) { section in
                SectionIconButton(symbol: section.symbol, title: section.title, isSelected: section == selected,
                              namespace: selection, onHoverEnter: onHoverIcon) { select(section) }
                    .notchTransition(.fade)
            }
        }
        .notchAnimation(value: sections)
    }
}

private struct SectionIconButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    /// Kayan seçim zemini için; ••• kendi zeminini çizer.
    let namespace: Namespace.ID?
    /// İmleç simgeye girince (dokunsal çentik).
    let onHoverEnter: () -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchDesign.Icon.regular, weight: NotchDesign.Icon.weight))
                .frame(width: NotchDesign.sectionIconSize, height: NotchDesign.Control.small)
                .foregroundStyle(Color.white.opacity(isSelected ? 1
                                                     : (isHovering ? NotchDesign.hoverIconOpacity : NotchDesign.inactiveIconOpacity)))
                .background { background }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            if inside, !isHovering { onHoverEnter() }
            isHovering = inside
        }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: NotchDesign.Radius.small, style: .continuous)
        if isSelected {
            if let namespace {
                shape.fill(NotchDesign.selectionFill).matchedGeometryEffect(id: "selection", in: namespace)
            } else {
                shape.fill(NotchDesign.selectionFill)
            }
        } else if isHovering {
            shape.fill(NotchDesign.cardFill)
        }
    }
}
