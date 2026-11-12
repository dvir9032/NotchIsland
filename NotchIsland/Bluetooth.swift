import Foundation
import IOBluetooth

/// Announces Bluetooth devices connecting and disconnecting, with AirPods-style battery when available.
final class BluetoothMonitor: NSObject {
    struct Event: Equatable {
        var name: String
        var symbol: String
        var connected: Bool
        var battery: Int?
    }

    var onEvent: ((Event) -> Void)?
    private var startedAt = Date()
    private var connectNote: IOBluetoothUserNotification?

    func start() {
        startedAt = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        // Registration replays devices that were already connected; only announce real arrivals.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        // Battery levels arrive a moment after the link comes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.onEvent?(Self.event(for: device, connected: true))
        }
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        onEvent?(Self.event(for: device, connected: false))
    }

    private static func event(for d: IOBluetoothDevice, connected: Bool) -> Event {
        let name = d.name ?? "Bluetooth"
        return Event(name: name, symbol: symbol(for: d, name: name), connected: connected, battery: connected ? battery(of: d) : nil)
    }

    private static func battery(of d: IOBluetoothDevice) -> Int? {
        func read(_ key: String) -> Int? {
            guard d.responds(to: NSSelectorFromString(key)), let n = d.value(forKey: key) as? NSNumber, n.intValue > 0 else { return nil }
            return n.intValue
        }
        let buds = [read("batteryPercentLeft"), read("batteryPercentRight")].compactMap { $0 }
        if let low = buds.min() { return low }
        return read("batteryPercentSingle") ?? read("batteryPercentCombined")
    }

    private static func symbol(for d: IOBluetoothDevice, name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpods.max" }
        if n.contains("airpods pro") { return "airpods.pro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("mouse") { return "magicmouse" }
        if n.contains("controller") || n.contains("dualsense") || n.contains("xbox") { return "gamecontroller.fill" }
        switch d.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio): return "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral): return "keyboard"
        case UInt32(kBluetoothDeviceClassMajorPhone): return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
