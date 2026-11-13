import AppKit
import UniformTypeIdentifiers

/// Files parked in the island: drop them in, drag them out later. Stores references, not copies.
final class Shelf: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let key = "shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        // Files are stored as paths, web links as full URL strings.
        items = paths.compactMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0) }
            .filter { !$0.isFileURL || FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
        save()
    }

    /// Forget files that were moved or deleted since they were parked. Links always stay.
    func pruneMissing() {
        let alive = items.filter { !$0.isFileURL || FileManager.default.fileExists(atPath: $0.path) }
        guard alive.count != items.count else { return }
        items = alive
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Self.loadURLs(providers) { [weak self] urls in self?.add(urls) }
    }

    /// Dropped straight onto the AirDrop target: send without parking on the shelf.
    func handleAirDropDrop(_ providers: [NSItemProvider]) -> Bool {
        Self.loadURLs(providers) { [weak self] urls in self?.airDrop(urls) }
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        // The AirDrop picker only comes forward for an active app.
        NSApp.activate()
        service.perform(withItems: urls)
    }

    private static func loadURLs(_ providers: [NSItemProvider], then done: @escaping ([URL]) -> Void) -> Bool {
        // public.url covers both files and web links (a Safari tab, an address-bar URL).
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in fileProviders {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
        return true
    }

    /// Files and links on a drag pasteboard; an address dragged as plain text counts too.
    static func links(on pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if !urls.isEmpty { return urls }
        return (pb.string(forType: .string) ?? "")
            .split(whereSeparator: \.isNewline)
            .compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    /// Whether a drag pasteboard carries something the island takes.
    static func hasLinks(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        // A tab dragged along Safari's tab bar never reaches other apps; don't open for it.
        if types.contains(.init("com.apple.safari.tab")), !types.contains(.URL) { return false }
        return types.contains(.fileURL) || types.contains(.URL) || !links(on: pb).isEmpty
    }

    // MARK: Current Safari tab

    /// A Safari tab dragged from the tab bar stays inside Safari (it's a tab move), so it can't be
    /// dropped here. These ask Safari for the front tab's address instead.
    func airDropSafariTab() {
        Self.currentSafariTab { [weak self] url in self?.airDrop([url]) }
    }

    func keepSafariTab() {
        Self.currentSafariTab { [weak self] url in self?.add([url]) }
    }

    static var safariRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty
    }

    /// osascript off the main thread: the first run waits on the Automation prompt.
    private static func currentSafariTab(_ done: @escaping (URL) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"Safari\" to return URL of current tab of front window"]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try? p.run()
            p.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if let url = URL(string: text), url.scheme != nil {
                    done(url)
                } else {
                    NSSound.beep()
                    // -1743: the user hasn't allowed controlling Safari.
                    if error.contains("-1743") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map { $0.isFileURL ? $0.path : $0.absoluteString }, forKey: key)
    }
}
