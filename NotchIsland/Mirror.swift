import AVFoundation
import SwiftUI

/// Front camera preview, running only while the mirror is on screen.
final class Mirror: ObservableObject {
    @Published private(set) var denied = false
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ni.mirror")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.run() : (self.denied = true) }
            }
        default:
            denied = true
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func run() {
        denied = false
        queue.async {
            if !self.configured {
                self.configured = true
                self.session.sessionPreset = .high
                if let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
}

struct MirrorPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            preview.videoGravity = .resizeAspectFill
            preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))  // a mirror, not a camera
            layer?.addSublayer(preview)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            // bounds + position, not frame: the layer carries a flip transform.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.bounds = bounds
            preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
}
