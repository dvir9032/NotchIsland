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

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.transform = CATransform3DMakeScale(-1, 1, 1)  // a mirror, not a camera
        v.layer = layer
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
