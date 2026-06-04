import Foundation

// Persisted to disk so the app shows data instantly on launch while it refetches.
struct SnipeDataCacheSnapshot: Codable {
    var assets: [Asset] = []
    var users: [User] = []
    var accessories: [Accessory] = []
    var licenses: [License] = []
    var consumables: [Consumable] = []
    var components: [Component] = []
    var locations: [Location] = []
    var companies: [Company] = []
    var manufacturers: [Manufacturer] = []
    var suppliers: [Supplier] = []
    var statusLabels: [StatusLabel] = []
    var savedAt: TimeInterval = Date().timeIntervalSince1970
}

// JSON file cache, one file per server so switching servers never mixes data.
enum LocalCacheStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("SnipeDataCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(key: String) -> URL? {
        directory?.appendingPathComponent("\(key).json")
    }

    // Stable, filename-safe key from a base URL.
    static func key(forBaseURL baseURL: String) -> String {
        let raw = baseURL.isEmpty ? "default" : baseURL
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let safe = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return safe.isEmpty ? "default" : safe
    }

    static func load(key: String) -> SnipeDataCacheSnapshot? {
        guard let url = fileURL(key: key), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SnipeDataCacheSnapshot.self, from: data)
    }

    static func save(_ snapshot: SnipeDataCacheSnapshot, key: String) {
        guard let url = fileURL(key: key) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // Wipe all cached files (on logout / data wipe).
    static func clearAll() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
