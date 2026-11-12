import SwiftUI
import UniformTypeIdentifiers

/// The notch outline: flared top corners that melt into the screen edge, rounded bottom corners.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let b = min(bottom, r.height / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + b, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - b), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let size = model.size
        let shape = NotchShape(top: model.topRadius, bottom: model.bottomRadius)
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                // Idle, the hardware notch is already black; drawing over it only shows our outline.
                .opacity(model.isOpen || model.activity != nil ? 1 : 0)
                .shadow(color: .black.opacity(model.isOpen ? 0.5 : 0), radius: 16, y: 8)
            Group {
                if model.isOpen {
                    ExpandedView(model: model)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.08)),
                                                removal: .opacity.animation(.easeIn(duration: 0.1))))
                } else if let a = model.activity {
                    CompactView(model: model, activity: a)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onTapGesture { if !model.isOpen { model.isOpen = true } }
        .contextMenu {
            Button("Settings…") { model.openSettings() }
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { _ in model.toggleLaunchAtLogin() }))
            Divider()
            Button("Quit Notch Island") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The whole canvas takes drops, so near-misses around the island still land on the shelf.
        // The panel only accepts the mouse inside the controller's hover zone anyway.
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { model.shelf.handleDrop($0) }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.isOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.activity)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Closed: live activity beside the notch

struct CompactView: View {
    @ObservedObject var model: IslandModel
    let activity: IslandModel.Activity

    var body: some View {
        let side = model.sideWidth(for: activity)
        HStack(spacing: 0) {
            leading.frame(width: side, alignment: .leading).padding(.leading, 10)
            Color.clear.frame(width: model.notch.width - 20)
            trailing.frame(width: side, alignment: .trailing).padding(.trailing, 10)
        }
        .frame(height: model.notch.height)
        .padding(.horizontal, model.topRadius)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .music:
            ArtworkView(media: model.media, size: model.notch.height - 10, radius: 5)
        case .timer:
            Image(systemName: "timer").foregroundStyle(.orange).font(.system(size: 14, weight: .semibold))
        case .timerDone:
            Image(systemName: "bell.fill").foregroundStyle(.orange).font(.system(size: 14, weight: .semibold))
                .symbolEffect(.wiggle, options: .repeating)
        case .charging:
            Image(systemName: "bolt.fill").foregroundStyle(.green).font(.system(size: 14, weight: .bold))
        case .lowBattery:
            Image(systemName: "battery.25percent").foregroundStyle(.red).font(.system(size: 15))
        case .bluetooth:
            if let e = model.btEvent {
                Image(systemName: Self.validSymbol(e.symbol))
                    .font(.system(size: 15))
                    .foregroundStyle(e.connected ? .white : .white.opacity(0.45))
            }
        }
    }

    private static func validSymbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "headphones"
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .music:
            EqualizerBars(playing: model.media.isPlaying, color: model.media.accent)
                .frame(width: 18, height: 13)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(IslandTimer.format(model.timer.remaining(at: ctx.date)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        case .timerDone:
            Text("Time's up").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case .charging:
            Text("\(model.battery.level)%").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.green)
        case .lowBattery:
            Text("\(model.battery.level)%").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.red)
        case .bluetooth:
            if let e = model.btEvent {
                Group {
                    if !e.connected {
                        Text("Disconnected").foregroundStyle(.white.opacity(0.5))
                    } else if let b = e.battery {
                        Text("\(b)%").foregroundStyle(b <= 20 ? .red : .green)
                    } else {
                        Text("Connected").foregroundStyle(.white.opacity(0.8))
                    }
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .help(e.name)
            }
        }
    }
}

/// Bouncing bars beside the notch. Core Animation runs them in the render server,
/// so they cost the app ~nothing for as long as a song plays.
struct EqualizerBars: NSViewRepresentable {
    let playing: Bool
    let color: Color

    final class BarsView: NSView {
        private var bars: [CALayer] = []
        private var animating = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<4 {
                let bar = CALayer()
                bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let w: CGFloat = 2.6, gap: CGFloat = 2
            let total = w * CGFloat(bars.count) + gap * CGFloat(bars.count - 1)
            var x = (bounds.width - total) / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars {
                bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
                bar.position = CGPoint(x: x + w / 2, y: bounds.midY)
                bar.cornerRadius = w / 2
                x += w + gap
            }
            CATransaction.commit()
        }

        func update(playing: Bool, color: NSColor) {
            for bar in bars { bar.backgroundColor = color.cgColor }
            guard playing != animating else { return }
            animating = playing
            for (i, bar) in bars.enumerated() {
                bar.removeAllAnimations()
                if playing {
                    let a = CABasicAnimation(keyPath: "transform.scale.y")
                    a.fromValue = 0.3
                    a.toValue = 1.0
                    a.duration = [0.42, 0.33, 0.51, 0.37][i]
                    a.beginTime = CACurrentMediaTime() + Double(i) * 0.11
                    a.autoreverses = true
                    a.repeatCount = .infinity
                    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bar.add(a, forKey: "bounce")
                } else {
                    bar.transform = CATransform3DMakeScale(1, 0.25, 1)
                }
            }
            if playing { for bar in bars { bar.transform = CATransform3DIdentity } }
        }
    }

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ view: BarsView, context: Context) {
        view.update(playing: playing, color: NSColor(color))
    }
}

struct ArtworkView: View {
    @ObservedObject var media: MediaController
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = media.appIcon {
                Image(nsImage: icon).resizable().padding(size * 0.08)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Open

struct ExpandedView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow(model: model)
                .frame(height: model.notch.height)
            if model.draggingFiles {
                HStack(spacing: 12) {
                    DropZone(targeted: model.dropTargeted, count: model.shelf.items.count)
                    AirDropZone(shelf: model.shelf)
                        .frame(width: 170)
                }
                .padding(.top, 10)
                .padding(.bottom, 18)
                .padding(.horizontal, 22)
            } else if model.showMirror {
                MirrorCard(model: model)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 16)
            } else {
                cards
            }
        }
        .padding(.horizontal, model.topRadius)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.18), value: model.draggingFiles)
    }

    private var cards: some View {
            HStack(alignment: .top, spacing: 16) {
                MediaCard(media: model.media, nudge: model.nudge)
                    .frame(width: 300)
                Divider().overlay(Color.white.opacity(0.08))
                TimerCard(timer: model.timer)
                    .frame(width: 118)
                Divider().overlay(Color.white.opacity(0.08))
                ShelfCard(shelf: model.shelf, targeted: model.dropTargeted)
            }
            .padding(.top, 12)
            .padding(.bottom, 18)
            .padding(.horizontal, 22)
    }
}

struct AirDropZone: View {
    @ObservedObject var shelf: Shelf
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .foregroundStyle(targeted ? Color.blue : .white.opacity(0.3))
            .background(Color.blue.opacity(targeted ? 0.25 : 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 28))
                        .symbolEffect(.bounce, value: targeted)
                    Text("AirDrop").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(targeted ? .white : .white.opacity(0.7))
            }
            .scaleEffect(targeted ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
            .onDrop(of: [.fileURL], isTargeted: $targeted) { shelf.handleAirDropDrop($0) }
    }
}

struct MirrorCard: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var mirror: Mirror

    init(model: IslandModel) {
        self.model = model
        self.mirror = model.mirror
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if mirror.denied {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash").font(.system(size: 24))
                    Text("No camera access").font(.system(size: 13, weight: .semibold))
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.white.opacity(0.7))
            } else {
                MirrorPreview(session: mirror.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct DropZone: View {
    let targeted: Bool
    let count: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.3))
            .background(Color.accentColor.opacity(targeted ? 0.2 : 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 30))
                        .symbolEffect(.bounce, value: targeted)
                    (targeted ? Text("Release to add to the shelf") : Text("Drop here to keep on the shelf"))
                        .font(.system(size: 14, weight: .semibold))
                    if count > 0 {
                        Text("Already on the shelf: \(count)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .foregroundStyle(targeted ? .white : .white.opacity(0.7))
            }
            .scaleEffect(targeted ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
    }
}

struct HeaderRow: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            if model.showMirror {
                // The mirror island is narrow: only the close button fits beside the notch.
                mirrorButton
                Spacer(minLength: model.notch.width)
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if Prefs.showMirrorButton {
                    mirrorButton.padding(.leading, 6)
                }
                Spacer(minLength: model.notch.width + 24)
                if model.battery.hasBattery {
                    BatteryBadge(battery: model.battery)
                }
            }
        }
        .padding(.horizontal, model.showMirror ? 16 : 24)
    }

    private var mirrorButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { model.showMirror.toggle() }
        } label: {
            Image(systemName: model.showMirror ? "xmark.circle.fill" : "web.camera")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(model.showMirror ? 0.9 : 0.6))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(model.showMirror ? Text("Close mirror") : Text("Mirror"))
    }
}

struct BatteryBadge: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack(spacing: 5) {
            Text("\(battery.level)%").font(.system(size: 12, weight: .medium).monospacedDigit())
            Image(systemName: battery.charging || battery.pluggedIn ? "battery.100percent.bolt" : symbol)
                .font(.system(size: 14))
                .foregroundStyle(color, .white.opacity(0.7))
        }
        .foregroundStyle(.white.opacity(0.75))
        .environment(\.layoutDirection, .leftToRight)
    }

    private var symbol: String {
        switch battery.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var color: Color {
        if battery.charging || battery.pluggedIn { return .green }
        return battery.level <= 20 ? .red : .white.opacity(0.85)
    }
}

struct MediaCard: View {
    @ObservedObject var media: MediaController
    var nudge: CGFloat = 0

    var body: some View {
        if let track = media.track {
            HStack(spacing: 14) {
                ArtworkView(media: media, size: 84, radius: 14)
                    .offset(x: -nudge)
                    .overlay(alignment: .bottomLeading) {
                        if media.artwork != nil, let icon = media.appIcon {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24).offset(x: -6, y: 6)
                        }
                    }
                    .onTapGesture { media.openSourceApp() }
                    .help(media.appName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(track.artist.isEmpty ? media.appName : track.artist)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    Spacer(minLength: 4)
                    ProgressRow(media: media, track: track)
                    Controls(media: media, playing: track.playing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 104)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.white.opacity(0.35))
                Text("Nothing playing").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 104)
        }
    }
}

struct ProgressRow: View {
    @ObservedObject var media: MediaController
    let track: MediaController.Track
    @State private var scrub: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let elapsed = scrub ?? track.elapsed(at: ctx.date)
            let fraction = track.duration > 0 ? elapsed / track.duration : 0
            HStack(spacing: 8) {
                Text(Self.time(elapsed)).frame(width: 34, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(media.accent).frame(width: max(0, g.size.width * fraction))
                    }
                    .frame(height: scrub == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in scrub = max(0, min(1, v.location.x / g.size.width)) * track.duration }
                        .onEnded { _ in
                            if let s = scrub { media.seek(to: s) }
                            scrub = nil
                        })
                    .disabled(track.duration <= 0)
                }
                .frame(height: 12)
                Text(track.duration > 0 ? Self.time(track.duration) : "").frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    static func time(_ t: Double) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct Controls: View {
    @ObservedObject var media: MediaController
    let playing: Bool

    var body: some View {
        HStack(spacing: 26) {
            IconButton(symbol: "backward.fill", size: 15) { media.previous() }
            IconButton(symbol: playing ? "pause.fill" : "play.fill", size: 22) { media.togglePlay() }
            IconButton(symbol: "forward.fill", size: 15) { media.next() }
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct IconButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 14, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct TimerCard: View {
    @ObservedObject var timer: IslandTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timer").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            if timer.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                        Circle().trim(from: 0, to: 1 - timer.progress(at: ctx.date))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: ctx.date)
                        Text(IslandTimer.format(timer.remaining(at: ctx.date)))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    .frame(width: 56, height: 56)
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: 6) {
                    Chip(title: "+1") { timer.add(minutes: 1) }
                    Chip(title: "Stop", tint: .red) { timer.cancel() }
                }
            } else {
                HStack(spacing: 4) {
                    StepButton(symbol: "minus") { timer.adjustCustom(up: false) }
                    Text("\(timer.customMinutes)")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: timer.customMinutes)
                        .frame(maxWidth: .infinity)
                    StepButton(symbol: "plus") { timer.adjustCustom(up: true) }
                    StepButton(symbol: "play.fill", tint: .orange) { timer.start(minutes: Double(timer.customMinutes)) }
                }
                .environment(\.layoutDirection, .leftToRight)
                .help("Minutes — press ▶ to start")
                HStack(spacing: 4) {
                    ForEach([1, 5, 10, 25], id: \.self) { m in
                        Chip(title: "\(m)", compact: true) { timer.start(minutes: Double(m)) }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}

struct StepButton: View {
    let symbol: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: Circle())
                .foregroundStyle(tint)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

struct Chip: View {
    let title: LocalizedStringKey
    var tint: Color = .orange
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 5 : 7)
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct ShelfCard: View {
    @ObservedObject var shelf: Shelf
    let targeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shelf").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !shelf.items.isEmpty {
                    Button {
                        shelf.airDrop(shelf.items)
                    } label: {
                        Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("AirDrop everything")
                    Button("Clear") { shelf.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.2))
                    .background(targeted ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 18))
                            Text("Drop files here").font(.system(size: 11))
                        }
                        .foregroundStyle(.white.opacity(targeted ? 0.9 : 0.4))
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItem(url: url, shelf: shelf)
                        }
                    }
                }
                .background(targeted ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShelfItem: View {
    let url: URL
    @ObservedObject var shelf: Shelf

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(4)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Send with AirDrop") { shelf.airDrop([url]) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }
}
