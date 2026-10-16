import ActivityAPI
import Integrations
import NotchShell
import SwiftUI

enum NowFormat {
    /// 0–100 yüzde, yerele göre ("%22" Türkçe, "22%" İngilizce).
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
