import AppKit
import Combine
import ServiceManagement

final class IslandModel: ObservableObject {
    enum Activity: Equatable {
        case music, timer, charging, lowBattery, timerDone
    }

    @Published var isOpen = false
    @Published var dropTargeted = false
    @Published var draggingFiles = false
    @Published private(set) var flash: Activity?
    @Published var notch: CGSize

    let media = MediaController()
    let battery = BatteryMonitor()
    let timer = IslandTimer()
    let shelf = Shelf()

    private var bag = Set<AnyCancellable>()
    private var flashWork: DispatchWorkItem?
    private var lastLowWarning = 101

    init(notch: CGSize) {
        self.notch = notch
        for child in [media.objectWillChange, battery.objectWillChange, timer.objectWillChange, shelf.objectWillChange] {
            child.receive(on: DispatchQueue.main).sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        }
        battery.onPowerChange = { [weak self] plugged in
            if plugged { self?.show(.charging, for: 3.5) }
        }
        battery.$level.sink { [weak self] level in self?.checkLow(level) }.store(in: &bag)
        timer.onFinish = { [weak self] in self?.show(.timerDone, for: 8) }
    }

    /// What the closed island shows beside the notch, most urgent first.
    var activity: Activity? {
        if let flash { return flash }
        if timer.isRunning { return .timer }
        if media.isPlaying { return .music }
        return nil
    }

    // MARK: Geometry

    var topRadius: CGFloat { isOpen ? 14 : 6 }
    var bottomRadius: CGFloat { isOpen ? 28 : 10 }
    static let openBody = CGSize(width: 640, height: 146)

    func sideWidth(for a: Activity) -> CGFloat {
        switch a {
        case .music: return notch.height + 16
        case .timer, .timerDone: return 74
        case .charging, .lowBattery: return 64
        }
    }

    /// Full island size, including the flared top corners.
    var size: CGSize {
        if isOpen {
            return CGSize(width: Self.openBody.width + topRadius * 2, height: notch.height + Self.openBody.height)
        }
        let side = activity.map(sideWidth(for:)) ?? 0
        return CGSize(width: notch.width + side * 2 + topRadius * 2, height: notch.height)
    }

    // MARK: Transient activities

    func show(_ a: Activity, for seconds: TimeInterval) {
        flashWork?.cancel()
        flash = a
        let work = DispatchWorkItem { [weak self] in self?.flash = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func dismissFlash() {
        flashWork?.cancel()
        flash = nil
    }

    private func checkLow(_ level: Int) {
        guard battery.hasBattery, !battery.pluggedIn else {
            lastLowWarning = 101
            return
        }
        for threshold in [20, 10, 5] where level <= threshold && lastLowWarning > threshold {
            lastLowWarning = threshold
            DispatchQueue.main.async { self.show(.lowBattery, for: 4) }
            return
        }
    }

    // MARK: Login item

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func toggleLaunchAtLogin() {
        do {
            if launchesAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("NotchIsland: login item: \(error)")
        }
        objectWillChange.send()
    }
}
