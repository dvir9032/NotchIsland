import AppKit

/// Built-in display brightness through the private DisplayServices framework.
enum SystemBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = dlsym(lib, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = dlsym(lib, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    private static let registerFn = dlsym(lib, "DisplayServicesRegisterForBrightnessChangeNotifications").map { unsafeBitCast($0, to: RegisterFn.self) }
    private static var handler: ((Float) -> Void)?

    private static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var value: Float? {
        var b: Float = 0
        guard let getFn, getFn(display, &b) == 0 else { return nil }
        return b
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let setFn else { return false }
        return setFn(display, min(1, max(0, value))) == 0
    }

    /// Calls `handler` on the main queue with the new level whenever the brightness changes,
    /// whoever changed it (keys, Control Center, auto-brightness). Needs no permission.
    static func observe(_ handler: @escaping (Float) -> Void) {
        guard let registerFn else { return }
        Self.handler = handler
        _ = registerFn(display, UnsafeRawPointer(bitPattern: 1)) { _, _, _, _, info in
            guard let info = info as NSDictionary?, let v = (info["value"] as? NSNumber)?.floatValue
                ?? Float(info["value"] as? String ?? "") else { return }
            DispatchQueue.main.async { SystemBrightness.handler?(v) }
        }
    }
}
