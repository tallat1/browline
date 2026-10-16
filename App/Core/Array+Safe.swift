import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
