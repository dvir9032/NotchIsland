import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // AppKit pushes windows below the menu bar; the island belongs on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    /// Takes link drops SwiftUI refuses: a source that only offers "move", or an address dragged
    /// as plain text. SwiftUI's drop asks for "copy" and URL types, so those would bounce off.
    var fallbackHover: ((NSDraggingInfo?) -> Void)?
    var fallbackDrop: ((NSDraggingInfo) -> Bool)?
    private var usingFallback = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// SwiftUI registers only the types its onDrop names, and re-registers on updates.
    /// Keep files, links and plain-text addresses in the set whatever it asks for.
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        let extra: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]
        super.registerForDraggedTypes(Array(Set(newTypes + extra)))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        route(super.draggingEntered(sender), sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        route(super.draggingUpdated(sender), sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        if usingFallback { fallbackHover?(nil) }
        usingFallback = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        usingFallback || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard usingFallback else { return super.performDragOperation(sender) }
        fallbackHover?(nil)
        return fallbackDrop?(sender) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if usingFallback { usingFallback = false } else { super.concludeDragOperation(sender) }
    }

    private func route(_ swiftUI: NSDragOperation, _ sender: NSDraggingInfo) -> NSDragOperation {
        guard swiftUI.isEmpty, fallbackDrop != nil, !Shelf.links(on: sender.draggingPasteboard).isEmpty else {
            usingFallback = false
            return swiftUI
        }
        usingFallback = true
        fallbackHover?(sender)
        let allowed = sender.draggingSourceOperationMask
        return [NSDragOperation.copy, .link, .generic, .move].first { allowed.contains($0) } ?? []
    }
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
    private var dragPoll: Timer?
    /// The drag pasteboard's changeCount while no button is held; a drag bumps it.
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var pressWatch: Timer?
    private var swipe = CGVector.zero
    private var swipeFired = false
    /// After a swipe-up closes the island, don't reopen it until the pointer leaves.
    private var holdClosed = false

    private static let canvas = CGSize(width: 780, height: 260)

    init() {
        screen = Self.pickScreen()
        model = IslandModel(notch: Self.notchSize(of: screen))
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true  // before `level`: it resets the level to .floating
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        let host = IslandHostingView(rootView: IslandView(model: model))
        panel.contentView = host
        place()
        panel.orderFrontRegardless()
        host.registerForDraggedTypes([])
        host.fallbackHover = { [weak self] info in self?.dropHover(info) }
        host.fallbackDrop = { [weak self] info in self?.dropLinks(info) ?? false }
        if UserDefaults.standard.bool(forKey: "debugOpen") { pinnedOpen = true; model.isOpen = true; panel.ignoresMouseEvents = false }

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.track() }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in self?.track(); return e }) {
            monitors.append(l)
        }
        if let s = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in self?.scrolled(e) ?? e }) {
            monitors.append(s)
        }
        // File drags from Finder don't reliably reach event monitors, so watch the drag pasteboard
        // from mouse-down until release.
        if let d = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in self?.watchForDrag() }) {
            monitors.append(d)
        }
        // Some drags never show a mouse-down to other apps, such as ones that start in a window's
        // title bar, which the window server handles. A slow check of the button catches those.
        pressWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.dragPoll == nil else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.watchForDrag()
            } else {
                self.dragBaseline = NSPasteboard(name: .drag).changeCount
            }
        }
        pressWatch?.tolerance = 0.1
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

    // MARK: Trackpad gestures

    /// Two-finger swipes over the open island: sideways on the player skips tracks, up closes.
    private func scrolled(_ e: NSEvent) -> NSEvent? {
        guard model.isOpen, e.hasPreciseScrollingDeltas else { return e }
        switch e.phase {
        case .began:
            swipe = .zero
            swipeFired = false
        case .changed:
            break
        default:
            return e
        }
        // Normalise to finger movement whatever the natural-scrolling setting is.
        let sign: CGFloat = e.isDirectionInvertedFromDevice ? 1 : -1
        swipe.dx += e.scrollingDeltaX * sign
        swipe.dy += e.scrollingDeltaY * sign
        guard !swipeFired else { return nil }

        let horizontal = abs(swipe.dx) > 55 && abs(swipe.dx) > abs(swipe.dy) * 1.5
        let up = swipe.dy < -45 && abs(swipe.dy) > abs(swipe.dx) * 1.5
        if horizontal, model.media.track != nil, !model.showMirror, overPlayer() {
            swipeFired = true
            let toNext = swipe.dx < 0  // fingers to the left, like flicking a card away
            toNext ? model.media.next() : model.media.previous()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(.easeOut(duration: 0.12)) { model.nudge = toNext ? -18 : 18 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.12)) { model.nudge = 0 }
            return nil
        }
        if up {
            swipeFired = true
            holdClosed = true
            closeWork?.cancel()
            closeWork = nil
            model.isOpen = false
            panel.ignoresMouseEvents = true
            return nil
        }
        return e
    }

    /// The player is the leading column of the open island (right in Hebrew, left in English);
    /// the shelf at the other end keeps its own horizontal scrolling.
    private func overPlayer() -> Bool {
        let r = islandRect()
        let x = NSEvent.mouseLocation.x
        let width = model.topRadius + 360
        return NSApp.userInterfaceLayoutDirection == .rightToLeft ? x > r.maxX - width : x < r.minX + width
    }

    // MARK: File drags

    private func overAirDropZone(_ p: NSPoint) -> Bool {
        // The AirDrop target is the trailing 170 pt of the open island's drop row.
        let r = islandRect()
        let inset = model.topRadius + 22
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        return rtl ? p.x < r.minX + inset + 170 : p.x > r.maxX - inset - 170
    }

    private func dropHover(_ info: NSDraggingInfo?) {
        guard let info else {
            model.dropTargeted = false
            model.airDropTargeted = false
            return
        }
        let air = model.isOpen && model.draggingFiles && overAirDropZone(panel.convertPoint(toScreen: info.draggingLocation))
        model.airDropTargeted = air
        model.dropTargeted = !air
    }

    private func dropLinks(_ info: NSDraggingInfo) -> Bool {
        let urls = Shelf.links(on: info.draggingPasteboard)
        let air = model.isOpen && model.draggingFiles && overAirDropZone(panel.convertPoint(toScreen: info.draggingLocation))
        guard !urls.isEmpty else { return false }
        air ? model.shelf.airDrop(urls) : model.shelf.add(urls)
        return true
    }

    private func watchForDrag() {
        guard dragPoll == nil else { return }
        dragPoll = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.dragTick() }
    }

    private func dragTick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            dragPoll?.invalidate()
            dragPoll = nil
            dragBaseline = NSPasteboard(name: .drag).changeCount
            if model.draggingFiles {
                // Let the drop land before the zone shrinks back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.model.draggingFiles = false
                    self?.track()
                }
            }
            return
        }
        if !model.draggingFiles {
            let pb = NSPasteboard(name: .drag)
            // Files from Finder, or a link (an address-bar URL, a link in a page).
            guard pb.changeCount != dragBaseline, Shelf.hasLinks(pb) else { return }
            model.draggingFiles = true
        }
        track()
    }

    /// Where the pointer counts as "on the island". While files are dragged the zone is generous,
    /// so a drag aimed roughly at the notch is enough.
    private func hoverZone() -> NSRect {
        var r = islandRect()
        if model.draggingFiles {
            r = model.isOpen ? r.insetBy(dx: -40, dy: -40) : r.insetBy(dx: -90, dy: -110)
        } else if model.isOpen {
            // An open island forgives small overshoots.
            r = r.insetBy(dx: -14, dy: -14)
        } else {
            // Closed, only the notch itself opens the island: a live activity beside it sits over
            // menu-bar items, and those must stay reachable.
            let w = model.notch.width + model.topRadius * 2
            r = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - model.notch.height,
                       width: w, height: model.notch.height).insetBy(dx: -4, dy: 0)
        }
        r.size.height += 4
        return r
    }

    private func track() {
        guard !pinnedOpen else { return }
        let p = NSEvent.mouseLocation
        let inside = hoverZone().contains(p)
        panel.ignoresMouseEvents = !inside
        if holdClosed {
            if inside { return }
            holdClosed = false
        }

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
                // A short dwell, so passing through on the way to the menu bar doesn't open it.
                DispatchQueue.main.asyncAfter(deadline: .now() + (model.draggingFiles ? 0 : Prefs.hoverDelay), execute: w)
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
        hoverZone().contains(NSEvent.mouseLocation)
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
