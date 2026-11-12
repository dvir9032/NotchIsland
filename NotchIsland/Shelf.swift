import AppKit
import UniformTypeIdentifiers

/// Files parked in the island: drop them in, drag them out later. Stores references, not copies.
final class Shelf: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let key = "shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
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
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for p in fileProviders {
            _ = p.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
        return true
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}
