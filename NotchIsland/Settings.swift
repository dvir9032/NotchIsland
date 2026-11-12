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
            Section("מה מופיע ליד הנוצ'") {
                Toggle("מוזיקה שמתנגנת", isOn: $showMusic)
                Toggle("טיימר פעיל", isOn: $showTimer)
                Toggle("טעינה וסוללה חלשה", isOn: $showBattery)
                Toggle("חיבור מכשירי בלוטות'", isOn: $showBluetooth)
            }
            Section("פתיחה") {
                Picker("מהירות פתיחה במעבר עכבר", selection: $hoverDelay) {
                    Text("מהירה").tag(0.1)
                    Text("רגילה").tag(0.2)
                    Text("איטית").tag(0.45)
                }
                Toggle("כפתור מראה", isOn: $showMirrorButton)
            }
            Section {
                Toggle("הפעלה עם ההתחברות", isOn: Binding(get: { model.launchesAtLogin }, set: { _ in model.toggleLaunchAtLogin() }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
        .environment(\.layoutDirection, .rightToLeft)
    }
}

final class SettingsWindow {
    private var window: NSWindow?

    func show(model: IslandModel) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "הגדרות האי הדינמי"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
