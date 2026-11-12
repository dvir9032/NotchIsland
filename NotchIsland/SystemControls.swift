import AppKit
import AudioToolbox
import CoreAudio

/// Output volume of the default device through CoreAudio.
enum SystemAudio {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static var outputDevice: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    static var volume: Float? {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        return AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static var isMuted: Bool {
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = address(kAudioDevicePropertyMute)
        return AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &m) == noErr && m != 0
    }

    @discardableResult
    static func setVolume(_ value: Float) -> Bool {
        var v = Float32(min(1, max(0, value)))
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        let dev = outputDevice
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { return false }
        return AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        var m: UInt32 = muted ? 1 : 0
        var a = address(kAudioDevicePropertyMute)
        return AudioObjectSetPropertyData(outputDevice, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m) == noErr
    }

    /// Calls `handler` on the main queue whenever volume, mute or the output device changes.
    static func observe(_ handler: @escaping () -> Void) {
        let queue = DispatchQueue.main
        var watched = AudioDeviceID(0)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        func watch() {
            var vol = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var mute = address(kAudioDevicePropertyMute)
            if watched != 0 {
                AudioObjectRemovePropertyListenerBlock(watched, &vol, queue, block)
                AudioObjectRemovePropertyListenerBlock(watched, &mute, queue, block)
            }
            watched = outputDevice
            AudioObjectAddPropertyListenerBlock(watched, &vol, queue, block)
            AudioObjectAddPropertyListenerBlock(watched, &mute, queue, block)
        }
        watch()
        var dev = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &dev, queue) { _, _ in watch() }
    }
}

/// Built-in display brightness through the private DisplayServices framework.
enum SystemBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = dlsym(lib, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = dlsym(lib, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }

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
}

/// Takes over the volume and brightness keys (needs Accessibility), so the island's HUD
/// replaces the system one. A key is only swallowed when its action succeeded here.
final class MediaKeyTap {
    enum Kind { case volume, brightness }

    /// Called on the main thread after a key changed something: kind, new level 0…1, muted.
    var onChange: ((Kind, Float, Bool) -> Void)?
    private(set) var isActive = false

    private var tap: CFMachPort?
    private var retry: Timer?

    private static let systemDefined = CGEventType(rawValue: 14)!  // NSEventTypeSystemDefined

    func start(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            install()
        } else if retry == nil {
            // Install as soon as the user grants Accessibility in System Settings.
            retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard AXIsProcessTrusted() else { return }
                t.invalidate()
                self?.retry = nil
                self?.install()
            }
        }
    }

    private func install() {
        guard tap == nil else { return }
        let mask = (1 << Self.systemDefined.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            guard let ctx else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(ctx).takeUnretainedValue()
            return tap.handle(type, event)
        }, userInfo: me) else {
            NSLog("NotchIsland: event tap failed")
            return
        }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isActive = true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)

        // Some keyboards send brightness as plain key codes.
        if type == .keyDown || type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard code == 144 || code == 145 else { return Unmanaged.passUnretained(event) }
            if type == .keyDown, !brightness(up: code == 144, fine: fine) { return Unmanaged.passUnretained(event) }
            return nil
        }

        guard type == Self.systemDefined, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let key = (ns.data1 & 0xFFFF0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        let handled: Bool
        switch key {
        case 0: handled = !isDown || volume(step: 1, fine: fine)   // NX_KEYTYPE_SOUND_UP
        case 1: handled = !isDown || volume(step: -1, fine: fine)  // NX_KEYTYPE_SOUND_DOWN
        case 7: handled = !isDown || toggleMute()                  // NX_KEYTYPE_MUTE
        case 2: handled = !isDown || brightness(up: true, fine: fine)
        case 3: handled = !isDown || brightness(up: false, fine: fine)
        default: handled = false
        }
        return handled ? nil : Unmanaged.passUnretained(event)
    }

    private func volume(step: Float, fine: Bool) -> Bool {
        guard let v = SystemAudio.volume else { return false }
        let delta: Float = fine ? 1 / 64 : 1 / 16
        let target = ((v / delta).rounded() + step) * delta
        guard SystemAudio.setVolume(target) else { return false }
        if SystemAudio.isMuted { SystemAudio.setMuted(false) }
        onChange?(.volume, min(1, max(0, target)), false)
        return true
    }

    private func toggleMute() -> Bool {
        let muted = !SystemAudio.isMuted
        guard SystemAudio.setMuted(muted) else { return false }
        onChange?(.volume, SystemAudio.volume ?? 0, muted)
        return true
    }

    private func brightness(up: Bool, fine: Bool) -> Bool {
        guard let b = SystemBrightness.value else { return false }
        let delta: Float = fine ? 1 / 64 : 1 / 16
        let target = min(1, max(0, ((b / delta).rounded() + (up ? 1 : -1)) * delta))
        guard SystemBrightness.set(target) else { return false }
        onChange?(.brightness, target, false)
        return true
    }
}
