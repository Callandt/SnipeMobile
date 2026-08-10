import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSnapshotBuilder {
    private static let dueSoonDays = 7

    static func update(from snapshot: SnipeDataCacheSnapshot, baseURL: String, isConfigured: Bool) {
        let widgetSnapshot = build(from: snapshot, baseURL: baseURL, isConfigured: isConfigured)
        WidgetSnapshotStore.save(widgetSnapshot)
        reloadTimelines()
    }

    static func clear() {
        WidgetSnapshotStore.clear()
        reloadTimelines()
    }

    private static func build(from snapshot: SnipeDataCacheSnapshot, baseURL: String, isConfigured: Bool) -> WidgetSnapshot {
        let now = Date()
        let assets = snapshot.assets

        let overdueAssets = assets.filter { AuditDateClassifier.isOverdue($0, now: now) }
        let dueTodayAssets = assets.filter { AuditDateClassifier.isDueToday($0, now: now) }
        let dueSoonAssets = assets.filter { AuditDateClassifier.isDueSoon($0, now: now, dueSoonDays: dueSoonDays) }

        let sortedOverdue = AuditDateClassifier.sortByNextAuditDateThenTag(overdueAssets)
        let topOverdue = sortedOverdue.prefix(8).map {
            WidgetAuditItem(
                id: $0.id,
                tag: $0.decodedAssetTag,
                name: $0.decodedName
            )
        }

        let openMaintenance = snapshot.maintenances.filter { !$0.isCompleted }
        let topMaintenance = openMaintenance.prefix(8).map {
            WidgetMaintenanceItem(
                id: $0.id,
                title: $0.decodedTitle,
                assetTag: $0.assetTag
            )
        }

        let deployedCount = assets.filter { $0.assignedTo != nil }.count
        let lowStock = countLowStock(
            accessories: snapshot.accessories,
            consumables: snapshot.consumables,
            components: snapshot.components
        )
        let topLowStock = buildLowStockItems(
            accessories: snapshot.accessories,
            consumables: snapshot.consumables,
            components: snapshot.components
        )

        return WidgetSnapshot(
            isConfigured: isConfigured,
            serverHost: host(from: baseURL),
            savedAt: Date(),
            auditsOverdue: overdueAssets.count,
            auditsDueToday: dueTodayAssets.count,
            auditsDueSoon: dueSoonAssets.count,
            openMaintenance: openMaintenance.count,
            totalAssets: assets.count,
            deployedAssets: deployedCount,
            lowStockItems: lowStock,
            topOverdueAudits: topOverdue,
            topOpenMaintenance: topMaintenance,
            topLowStockItems: topLowStock
        )
    }

    private static func host(from baseURL: String) -> String? {
        guard let url = URL(string: baseURL), let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    private static func countLowStock(accessories: [Accessory], consumables: [Consumable], components: [Component]) -> Int {
        let accessoryCount = accessories.filter(isLowStock).count
        let consumableCount = consumables.filter(isLowStock).count
        let componentCount = components.filter(isLowStock).count
        return accessoryCount + consumableCount + componentCount
    }

    private static func isLowStock(_ item: Accessory) -> Bool {
        guard let min = item.minAmt, let remaining = item.remaining else { return false }
        return remaining <= min
    }

    private static func isLowStock(_ item: Consumable) -> Bool {
        guard let min = item.minAmt, let remaining = item.remaining else { return false }
        return remaining <= min
    }

    private static func isLowStock(_ item: Component) -> Bool {
        guard let min = item.minAmt, let remaining = item.remaining else { return false }
        return remaining <= min
    }

    private static func buildLowStockItems(
        accessories: [Accessory],
        consumables: [Consumable],
        components: [Component]
    ) -> [WidgetStockItem] {
        var items: [WidgetStockItem] = []

        for item in accessories where isLowStock(item) {
            items.append(WidgetStockItem(
                id: "acc-\(item.id)",
                name: item.decodedName,
                remaining: item.remaining ?? 0,
                kindLabel: "Accessory"
            ))
        }
        for item in consumables where isLowStock(item) {
            items.append(WidgetStockItem(
                id: "con-\(item.id)",
                name: item.decodedName,
                remaining: item.remaining ?? 0,
                kindLabel: "Consumable"
            ))
        }
        for item in components where isLowStock(item) {
            items.append(WidgetStockItem(
                id: "cmp-\(item.id)",
                name: item.decodedName,
                remaining: item.remaining ?? 0,
                kindLabel: "Component"
            ))
        }

        return items
            .sorted { $0.remaining < $1.remaining }
            .prefix(8)
            .map { $0 }
    }

    private static func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
