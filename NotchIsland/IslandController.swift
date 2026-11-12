import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // AppKit pushes windows below the menu bar; the island belongs on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the transparent panel over the notch and decides when the island opens:
/// the panel only takes the mouse while the pointer is over the island itself.
final class IslandController {
    let model: IslandModel
    private let panel: IslandPanel
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var poll: Timer?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var pinnedOpen = false

    private static let canvas = CGSize(width: 780, height: 240)

    init() {
        screen = Self.pickScreen()
        model = IslandModel(notch: Self.notchSize(of: screen))
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.contentView = IslandHostingView(rootView: IslandView(model: model))
        place()
        panel.orderFrontRegardless()
        if UserDefaults.standard.bool(forKey: "debugOpen") { pinnedOpen = true; model.isOpen = true; panel.ignoresMouseEvents = false }

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.track() }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in self?.track(); return e }) {
            monitors.append(l)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenChanged()
        }
    }

    // MARK: Screen

    private static func pickScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func notchSize(of s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        // No notch: a pill the height of the menu bar.
        return CGSize(width: 190, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
    }

    private func place() {
        let f = screen.frame
        panel.setFrame(NSRect(x: f.midX - Self.canvas.width / 2, y: f.maxY - Self.canvas.height,
                              width: Self.canvas.width, height: Self.canvas.height), display: true)
    }

    private func screenChanged() {
        screen = Self.pickScreen()
        model.notch = Self.notchSize(of: screen)
        place()
    }

    // MARK: Hover

    private func islandRect() -> NSRect {
        let s = model.size
        let f = screen.frame
        return NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    private func track() {
        guard !pinnedOpen else { return }
        let p = NSEvent.mouseLocation
        var r = islandRect()
        // Tolerances: the pointer can sit on the very top row, and an open island forgives small overshoots.
        r = model.isOpen ? r.insetBy(dx: -14, dy: -14) : r.insetBy(dx: -6, dy: 0)
        r.size.height += 4
        let inside = r.contains(p)
        panel.ignoresMouseEvents = !inside

        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !model.isOpen, openWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.openWork = nil
                    self.open()
                }
                openWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
            }
        } else {
            openWork?.cancel()
            openWork = nil
            if model.isOpen, closeWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    withAnimation { self.model.isOpen = false }
                    self.model.dropTargeted = false
                }
                closeWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
            }
        }
        // Mouse-moved events stop once the pointer rests over our own panel, so poll while it matters.
        if inside || model.isOpen { startPolling() } else { stopPolling() }
    }

    private func open() {
        guard isPointerNearIsland() else { return }
        if model.activity == .timerDone { model.dismissFlash() }
        model.isOpen = true
    }

    private func isPointerNearIsland() -> Bool {
        var r = islandRect().insetBy(dx: -6, dy: 0)
        r.size.height += 4
        return r.contains(NSEvent.mouseLocation)
    }

    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.track() }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }
}
