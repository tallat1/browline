import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

extension NowPlayingController.FallbackReason {
    var localizedText: String {
        switch self {
        case .adapterMissing: String(localized: "adaptör uygulama paketinde yok")
        case .adapterTestFailed: String(localized: "adaptör testi bu macOS sürümünde başarısız")
        case .adapterLaunchFailed: String(localized: "adaptör başlatılamadı")
        case let .adapterExited(status): String(localized: "adaptör \(Int(status)) koduyla kapandı")
        }
    }
}
