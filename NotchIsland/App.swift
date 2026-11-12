import AppKit
import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = IslandController()
        c.model.startServices()
        controller = c
        // `NotchIsland -launchAtLogin YES` turns the login item on from the command line.
        if UserDefaults.standard.bool(forKey: "launchAtLogin"), !c.model.launchesAtLogin {
            c.model.toggleLaunchAtLogin()
        }
    }

    /// Opening the app again (Spotlight, Finder) while it runs brings up the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.model.openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.model.media.stop()
        controller?.model.mirror.stop()
    }
}
