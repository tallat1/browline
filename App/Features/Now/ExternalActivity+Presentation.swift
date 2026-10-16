import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

extension ExternalActivity {
    /// Geçersiz ya da bu sistemde olmayan sembol adı yerine genel simge.
    var symbolName: String {
        guard let symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
            return "app.badge"
        }
        return symbol
    }

    var tintColor: Color {
        guard let tint, tint.count == 7, let value = UInt32(tint.dropFirst(), radix: 16) else { return .white }
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
