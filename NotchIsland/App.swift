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

    func applicationWillTerminate(_ notification: Notification) {
        controller?.model.media.stop()
        controller?.model.mirror.stop()
    }
}
