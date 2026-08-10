import Foundation

struct WidgetAuditItem: Codable, Identifiable, Hashable {
    let id: Int
    let tag: String
    let name: String
}

struct WidgetMaintenanceItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let assetTag: String?
}

struct WidgetStockItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let remaining: Int
    let kindLabel: String
}

struct WidgetSnapshot: Codable {
    var isConfigured: Bool = false
    var serverHost: String?
    var savedAt: Date = .distantPast

    var auditsOverdue: Int = 0
    var auditsDueToday: Int = 0
    var auditsDueSoon: Int = 0
    var openMaintenance: Int = 0
    var totalAssets: Int = 0
    var deployedAssets: Int = 0
    var lowStockItems: Int = 0

    var topOverdueAudits: [WidgetAuditItem] = []
    var topOpenMaintenance: [WidgetMaintenanceItem] = []
    var topLowStockItems: [WidgetStockItem] = []

    static let empty = WidgetSnapshot()

    var hasData: Bool {
        isConfigured && totalAssets > 0
    }

    var formattedSavedAt: String {
        guard savedAt != .distantPast else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: savedAt, relativeTo: Date())
    }

    var availableAssets: Int {
        max(totalAssets - deployedAssets, 0)
    }

    var hasActionItems: Bool {
        !topOverdueAudits.isEmpty || !topOpenMaintenance.isEmpty || !topLowStockItems.isEmpty
    }
}

enum WidgetSnapshotStore {
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetConstants.appGroupID)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(WidgetConstants.snapshotFileName)
    }

    static func load() -> WidgetSnapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
