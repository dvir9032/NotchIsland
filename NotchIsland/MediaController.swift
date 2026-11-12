import AppKit
import SwiftUI

/// Now Playing for any app (Music, Spotify, browsers…), through the NIHelper bridge
/// hosted in /usr/bin/perl — see NIHelper.m for why.
final class MediaController: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var elapsed: Double
        var timestamp: Date
        var rate: Double
        var playing: Bool
        var pid: Int32

        func elapsed(at now: Date) -> Double {
            guard playing else { return elapsed }
            let e = elapsed + now.timeIntervalSince(timestamp) * max(rate, 1)
            return duration > 0 ? min(e, duration) : e
        }
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var appName: String = ""

    var isPlaying: Bool { track?.playing == true }

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    /// Back-to-back bridge failures; each one doubles the wait before the next try.
    private var failures = 0
    private var startedAt = Date()

    private static let script = """
    use DynaLoader;
    my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($l, "ni_run") or die "ni_run missing";
    my $x = DynaLoader::dl_install_xsub("main::ni_run", $s);
    &$x();
    """

    func start() {
        guard process == nil else { return }
        guard let lib = Bundle.main.url(forResource: "NIHelper", withExtension: "dylib"),
              FileManager.default.fileExists(atPath: lib.path) else {
            NSLog("NotchIsland: NIHelper.dylib not found")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.script, lib.path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.bridgeExited() }
        }
        do {
            try p.run()
            startedAt = Date()
            process = p
            input = inp.fileHandleForWriting
        } catch {
            NSLog("NotchIsland: perl bridge failed: \(error)")
        }
    }

    private func bridgeExited() {
        process = nil
        input = nil
        buffer.removeAll()
        // A bridge that ran a while was healthy; only quick deaths count as failures.
        failures = Date().timeIntervalSince(startedAt) > 30 ? 0 : failures + 1
        guard failures <= 6 else {
            NSLog("NotchIsland: Now Playing bridge keeps failing, giving up")
            return
        }
        let delay = min(120, 2 * pow(2, Double(max(0, failures - 1))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    // MARK: Commands

    func togglePlay() {
        if var t = track {
            // Optimistic, so the button reacts before the player confirms.
            t.elapsed = t.elapsed(at: Date())
            t.timestamp = Date()
            t.playing.toggle()
            track = t
        }
        send("toggle")
    }

    func next() { send("next") }
    func previous() { send("prev") }

    func seek(to seconds: Double) {
        if var t = track {
            t.elapsed = seconds
            t.timestamp = Date()
            track = t
        }
        send("seek \(seconds)")
    }

    func openSourceApp() {
        guard let pid = track?.pid, pid > 0 else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func send(_ command: String) {
        input?.write(Data((command + "\n").utf8))
    }

    // MARK: Parsing

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                apply(obj)
            }
        }
    }

    private func apply(_ o: [String: Any]) {
        let title = o["title"] as? String ?? ""
        let pid = Int32(o["pid"] as? Int ?? 0)
        if let art = o["art"] as? String {
            if art.isEmpty {
                artwork = nil
            } else if let data = Data(base64Encoded: art), let img = NSImage(data: data) {
                artwork = img
            }
            accent = Self.accentColor(of: artwork)
        }
        guard !title.isEmpty else {
            track = nil
            return
        }
        track = Track(
            title: title,
            artist: o["artist"] as? String ?? "",
            album: o["album"] as? String ?? "",
            duration: (o["duration"] as? NSNumber)?.doubleValue ?? 0,
            elapsed: (o["elapsed"] as? NSNumber)?.doubleValue ?? 0,
            timestamp: Date(timeIntervalSince1970: (o["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970),
            rate: (o["rate"] as? NSNumber)?.doubleValue ?? 0,
            playing: o["playing"] as? Bool ?? false,
            pid: pid
        )
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
            appIcon = app.icon
            appName = app.localizedName ?? ""
        }
    }

    /// Average colour of the artwork, brightened so it reads on black.
    private static func accentColor(of image: NSImage?) -> Color {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let ns = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(s * 1.3, 0.85), brightness: max(b, 0.85))
    }
}
