import Foundation
import IOKit.ps

final class BatteryMonitor: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    @Published private(set) var hasBattery = false

    /// Called on the main thread when the charger is connected (true) or removed (false).
    var onPowerChange: ((Bool) -> Void)?

    private var source: CFRunLoopSource?

    init() {
        update(notify: false)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().update(notify: true)
        }, ctx)?.takeRetainedValue() {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func update(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let wasPlugged = pluggedIn
            hasBattery = true
            level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            charging = d[kIOPSIsChargingKey] as? Bool ?? false
            pluggedIn = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if notify, wasPlugged != pluggedIn { onPowerChange?(pluggedIn) }
            return
        }
    }
}
