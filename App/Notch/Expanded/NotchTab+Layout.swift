import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

extension NotchTab {
    /// Üç sabit boy (2026-10-16 denetimi: dokuz farklı boy vardı, bölüm içinde sayfa değişince notch
    /// zıplıyordu). Raf ile Pano aynı boyda; Araçlar'da içerik gereği farklı.
    static let shortHeight: CGFloat = 132
    static let mediumHeight: CGFloat = 200
    static let longHeight: CGFloat = 280

    /// İçerik alanının boyu (bant hariç). Genişlik hepsinde `NotchDesign.openWidth`.
    var bodyHeight: CGFloat {
        switch self {
        case .now, .activities, .calendar, .timer: Self.shortHeight
        // Sistem grafiklerle orta boyda: Durum bölümünün üç sayfası aynı boy, geçişte zıplama yok.
        case .shelf, .clipboard, .notes, .system, .claude, .ci: Self.mediumHeight
        case .terminal, .mirror: Self.longHeight
        }
    }
}
