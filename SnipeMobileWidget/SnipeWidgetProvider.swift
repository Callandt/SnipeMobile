import WidgetKit
import SwiftUI

struct SnipeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let displayMode: SnipeWidgetDisplayMode
}

struct SnipeWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnipeWidgetEntry {
        SnipeWidgetEntry(date: .now, snapshot: .preview, displayMode: .overview)
    }

    func snapshot(for configuration: SnipeWidgetConfigurationIntent, in context: Context) async -> SnipeWidgetEntry {
        makeEntry(configuration: configuration, isPreview: context.isPreview)
    }

    func timeline(for configuration: SnipeWidgetConfigurationIntent, in context: Context) async -> Timeline<SnipeWidgetEntry> {
        let entry = makeEntry(configuration: configuration, isPreview: context.isPreview)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func makeEntry(configuration: SnipeWidgetConfigurationIntent, isPreview: Bool) -> SnipeWidgetEntry {
        SnipeWidgetEntry(
            date: .now,
            snapshot: isPreview ? .preview : WidgetSnapshotStore.load(),
            displayMode: configuration.displayMode
        )
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        isConfigured: true,
        serverHost: "develop.snipeitapp.com",
        savedAt: .now,
        auditsOverdue: 3,
        auditsDueToday: 2,
        auditsDueSoon: 5,
        openMaintenance: 12,
        totalAssets: 2558,
        deployedAssets: 401,
        lowStockItems: 2,
        topOverdueAudits: [
            WidgetAuditItem(id: 1, tag: "LT-001", name: "MacBook Pro"),
            WidgetAuditItem(id: 2, tag: "LT-014", name: "Dell XPS"),
            WidgetAuditItem(id: 3, tag: "MON-08", name: "Monitor 27\"")
        ],
        topOpenMaintenance: [
            WidgetMaintenanceItem(id: 1, title: "Battery replacement", assetTag: "LT-001"),
            WidgetMaintenanceItem(id: 2, title: "Screen repair", assetTag: "LT-014")
        ],
        topLowStockItems: [
            WidgetStockItem(id: "1", name: "USB-C Kabel", remaining: 2, kindLabel: "Consumable"),
            WidgetStockItem(id: "2", name: "Docking station", remaining: 1, kindLabel: "Accessory")
        ]
    )
}
