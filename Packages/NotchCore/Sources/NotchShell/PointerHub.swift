import AppKit

/// Global fare izleyicileri. Hiçbiri izin istemez (yalnız tuş olayları Accessibility ister).
/// Açıkken izleme yalnız bir notch açıkken kurulur; sürükleme algılama yalnız tıklama ve
/// sürüklemede uyanır, boşta süreci uyandırmaz.
@MainActor
final class PointerHub {
    var onPointerMoved: ((CGPoint) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?
    var onFileDrag: ((_ active: Bool, _ point: CGPoint) -> Void)?

    private var trackingMonitors: [Any] = []
    private var dragMonitors: [Any] = []
    private var dragChangeCountAtMouseDown = 0
    private var isFileDragging = false

    var isTracking: Bool { !trackingMonitors.isEmpty }

    func setTracking(_ enabled: Bool) {
        guard enabled != isTracking else { return }
        guard enabled else {
            trackingMonitors.forEach(NSEvent.removeMonitor)
            trackingMonitors.removeAll()
            return
        }
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onPointerMoved?(NSEvent.mouseLocation) }
        }) {
            trackingMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.onPointerMoved?(NSEvent.mouseLocation) }
            return event
        }) {
            trackingMonitors.append(monitor)
        }
        // Başka uygulamaya giden tıklama = notch dışına tıklama.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                           handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onMouseDown?(NSEvent.mouseLocation) }
        }) {
            trackingMonitors.append(monitor)
        }
    }

    func setDragDetection(_ enabled: Bool) {
        guard enabled != !dragMonitors.isEmpty else { return }
        guard enabled else {
            dragMonitors.forEach(NSEvent.removeMonitor)
            dragMonitors.removeAll()
            return
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleDrag(type) }
        }) {
            dragMonitors.append(monitor)
        }
    }

    /// Sürükleme panosunun changeCount'u basıştan sonra değiştiyse ve dosya taşıyorsa bir dosya sürükleniyor.
    private func handleDrag(_ type: NSEvent.EventType) {
        let pasteboard = NSPasteboard(name: .drag)
        switch type {
        case .leftMouseDown:
            dragChangeCountAtMouseDown = pasteboard.changeCount
        case .leftMouseDragged:
            if !isFileDragging {
                // Dosya sözü de sayılır: ekran görüntüsü küçük resmi adres taşımaz.
                guard pasteboard.changeCount != dragChangeCountAtMouseDown,
                      FileDrop.carriesFiles(pasteboard) else { return }
                isFileDragging = true
            }
            onFileDrag?(true, NSEvent.mouseLocation)
        case .leftMouseUp:
            guard isFileDragging else { return }
            isFileDragging = false
            onFileDrag?(false, NSEvent.mouseLocation)
        default:
            break
        }
    }
}
