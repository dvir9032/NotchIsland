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

    private func save() {
        UserDefaults.standard.set(items.map { $0.isFileURL ? $0.path : $0.absoluteString }, forKey: key)
    }
}
