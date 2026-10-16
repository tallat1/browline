import AppKit
import AVFoundation
import NotchShell
import SwiftUI

/// Ayna: kamera yalnız bu sekme ekrandayken açık; notch kapanınca ya da sekme değişince durur.
/// Görüntü kaydedilmez, hiçbir yere gönderilmez.
struct MirrorTab: View {
    let mirror: CameraMirror
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        // İzin verilince istemden görüntüye çapraz geçiş.
        ZStack {
            stateContent
                .id(status.rawValue)
                .notchTransition(.swap)
        }
        .notchAnimation(value: status.rawValue)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch status {
        case .authorized:
            // Kare: sekme kendi boyunu kare ister (ExpandedView.bodySize).
            CameraPreview(session: mirror.session)
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { mirror.start() }
                .onDisappear { mirror.stop() }
        case .notDetermined:
            EmptyStateView(symbol: "person.crop.square", title: "Ayna",
                           message: "Kamera izni gerekiyor. Görüntü kaydedilmez, hiçbir yere gönderilmez.") {
                Button("Kameraya erişim ver") {
                    Task { @MainActor in
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        status = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .blue))
            }
        default:
            EmptyStateView(symbol: "video.slash", title: "Kamera izni kapalı",
                           message: "Gizlilik ayarlarından Browline'a izin verin.") {
                Button("Gizlilik ayarlarını aç") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(CapsuleButtonStyle())
            }
        }
    }
}

/// Kamera oturumu. `startRunning` bloklayıcı; oturum yalnız kendi kuyruğunda değiştirilir.
final class CameraMirror: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.talatozcoban.notchmvp.mirror")
    private var isConfigured = false

    func start() {
        queue.async { [self] in
            configureIfNeeded()
            if isConfigured, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Önce yerleşik kamera; yoksa (kapak kapalı) sistemin varsayılanı, Continuity Camera dahil.
    private func configureIfNeeded() {
        guard !isConfigured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)
        session.commitConfiguration()
        isConfigured = true
    }
}

/// Önizleme katmanı; ayna gibi yatay çevrilmiş.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ view: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
