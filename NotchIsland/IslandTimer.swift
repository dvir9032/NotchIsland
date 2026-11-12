import AppKit

final class IslandTimer: ObservableObject {
    @Published private(set) var end: Date?
    @Published private(set) var total: TimeInterval = 0

    var onFinish: (() -> Void)?
    var isRunning: Bool { end != nil }

    private var ticker: Timer?

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
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(now))
    }

    func progress(at now: Date = Date()) -> Double {
        total > 0 ? 1 - remaining(at: now) / total : 0
    }

    private func schedule() {
        ticker?.invalidate()
        guard let end else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: max(0.05, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            self?.end = nil
            NSSound(named: "Glass")?.play()
            self?.onFinish?()
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
