import AppKit

final class IslandTimer: ObservableObject {
    @Published private(set) var end: Date?
    @Published private(set) var total: TimeInterval = 0
    /// The custom duration picked with − / +, remembered between runs.
    @Published var customMinutes: Int = UserDefaults.standard.object(forKey: "timerCustomMinutes") as? Int ?? 15 {
        didSet { UserDefaults.standard.set(customMinutes, forKey: "timerCustomMinutes") }
    }

    var onFinish: (() -> Void)?
    var isRunning: Bool { end != nil }

    private var ticker: Timer?

    init() {
        // A timer survives a relaunch or a restart, as long as it hasn't run out meanwhile.
        let d = UserDefaults.standard
        if let saved = d.object(forKey: "timerEnd") as? Date, saved > Date() {
            end = saved
            total = d.double(forKey: "timerTotal")
            schedule()
        }
    }

    /// Steps of 1 minute up to 10, then 5 up to 60, then 15.
    func adjustCustom(up: Bool) {
        let m = customMinutes
        let step = up ? (m < 10 ? 1 : m < 60 ? 5 : 15) : (m <= 10 ? 1 : m <= 60 ? 5 : 15)
        customMinutes = min(180, max(1, m + (up ? step : -step)))
    }

    func start(minutes: Double) {
        total = minutes * 60
        end = Date().addingTimeInterval(total)
        schedule()
    }

    func add(minutes: Double) {
        guard let e = end else { return start(minutes: minutes) }
        end = e.addingTimeInterval(minutes * 60)
        total += minutes * 60
        schedule()
    }

    func cancel() {
        ticker?.invalidate()
        end = nil
        persist()
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(now))
    }

    func progress(at now: Date = Date()) -> Double {
        total > 0 ? 1 - remaining(at: now) / total : 0
    }

    private func schedule() {
        ticker?.invalidate()
        persist()
        guard let end else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: max(0.05, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            self?.end = nil
            self?.persist()
            NSSound(named: "Glass")?.play()
            self?.onFinish?()
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        if let end {
            d.set(end, forKey: "timerEnd")
            d.set(total, forKey: "timerTotal")
        } else {
            d.removeObject(forKey: "timerEnd")
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
