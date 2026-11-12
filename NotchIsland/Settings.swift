import AppKit
import SwiftUI

/// User preferences; every switch defaults to on.
enum Prefs {
    private static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    static var showMusic: Bool { flag("showMusic") }
    static var showTimer: Bool { flag("showTimer") }
    static var showBattery: Bool { flag("showBattery") }
    static var showBluetooth: Bool { flag("showBluetooth") }
    static var showMirrorButton: Bool { flag("showMirrorButton") }
    static var hoverDelay: Double { UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.2 }
}

struct SettingsView: View {
    @ObservedObject var model: IslandModel
    @AppStorage("showMusic") private var showMusic = true
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("showBattery") private var showBattery = true
    @AppStorage("showBluetooth") private var showBluetooth = true
    @AppStorage("showMirrorButton") private var showMirrorButton = true
    @AppStorage("hoverDelay") private var hoverDelay = 0.2

    var body: some View {
        Form {
            Section("Show beside the notch") {
                Toggle("Music playing", isOn: $showMusic)
                Toggle("Running timer", isOn: $showTimer)
                Toggle("Charging and low battery", isOn: $showBattery)
                Toggle("Bluetooth devices connecting", isOn: $showBluetooth)
            }
            Section("Opening") {
                Picker("Hover speed", selection: $hoverDelay) {
                    Text("Fast").tag(0.1)
                    Text("Normal").tag(0.2)
                    Text("Slow").tag(0.45)
                }
                Toggle("Mirror button", isOn: $showMirrorButton)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { _ in model.toggleLaunchAtLogin() }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}

final class SettingsWindow {
    private var window: NSWindow?

    func show(model: IslandModel) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = String(localized: "Notch Island Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
