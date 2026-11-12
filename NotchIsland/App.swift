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
        c.model.media.start()
        controller = c
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.model.media.stop()
    }
}
