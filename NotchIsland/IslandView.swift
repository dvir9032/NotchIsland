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
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { model.shelf.handleDrop($0) }
        .contextMenu {
            Button(model.launchesAtLogin ? "✓ הפעלה עם ההתחברות" : "הפעלה עם ההתחברות") { model.toggleLaunchAtLogin() }
            Divider()
            Button("יציאה מהאי הדינמי") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        }
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
            Text("הזמן נגמר").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case .charging:
            Text("\(model.battery.level)%").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.green)
        case .lowBattery:
            Text("\(model.battery.level)%").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.red)
        }
    }
}

struct EqualizerBars: View {
    let playing: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = Double(i) * 1.7
                    let h = playing ? 0.3 + 0.7 * abs(sin(t * (3.1 + Double(i) * 0.9) + phase)) : 0.25
                    Capsule().fill(color).frame(width: 2.6).frame(maxHeight: .infinity).scaleEffect(y: h)
                }
            }
        }
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
            HStack(alignment: .top, spacing: 16) {
                MediaCard(media: model.media)
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
        .padding(.horizontal, model.topRadius)
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct HeaderRow: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "he_IL"))))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: model.notch.width + 24)
            if model.battery.hasBattery {
                BatteryBadge(battery: model.battery)
            }
        }
        .padding(.horizontal, 24)
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

    var body: some View {
        if let track = media.track {
            HStack(spacing: 14) {
                ArtworkView(media: media, size: 84, radius: 14)
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
                Text("שום דבר לא מתנגן").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
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
            Text("טיימר").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
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
                    Chip(title: "עצור", tint: .red) { timer.cancel() }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach([1, 5, 10, 25], id: \.self) { m in
                        Chip(title: "\(m) דק׳") { timer.start(minutes: Double(m)) }
                    }
                }
            }
        }
    }
}

struct Chip: View {
    let title: String
    var tint: Color = .orange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
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
                Text("מדף").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !shelf.items.isEmpty {
                    Button("נקה") { shelf.clear() }
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
                            Text("גרור לכאן קבצים").font(.system(size: 11))
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
            Button("פתח") { NSWorkspace.shared.open(url) }
            Button("הצג ב-Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("הסר מהמדף") { shelf.remove(url) }
        }
        .help(url.path)
    }
}
