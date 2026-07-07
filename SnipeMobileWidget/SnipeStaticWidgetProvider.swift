import SwiftUI
import WidgetKit

struct SnipeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let displayMode: SnipeWidgetDisplayMode
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

struct SnipeStaticTimelineProvider: TimelineProvider {
    let displayMode: SnipeWidgetDisplayMode

    func placeholder(in context: Context) -> SnipeWidgetEntry {
        SnipeWidgetEntry(date: .now, snapshot: .preview, displayMode: displayMode)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnipeWidgetEntry) -> Void) {
        completion(makeEntry(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnipeWidgetEntry>) -> Void) {
        let entry = makeEntry(isPreview: context.isPreview)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry(isPreview: Bool) -> SnipeWidgetEntry {
        SnipeWidgetEntry(
            date: .now,
            snapshot: isPreview ? .preview : WidgetSnapshotStore.load(),
            displayMode: displayMode
        )
    }
}

enum SnipeWidgetKinds {
    static let overview = "SnipeOverviewWidget"
    static let audits = "SnipeAuditsWidget"
    static let maintenance = "SnipeMaintenanceWidget"
    static let assets = "SnipeAssetsWidget"
    static let stock = "SnipeStockWidget"
}

private let snipeHomeScreenFamilies: [WidgetFamily] = [
    .systemSmall,
    .systemMedium,
    .systemLarge,
]

private let snipeHomeScreenFamiliesCompact: [WidgetFamily] = [
    .systemSmall,
    .systemMedium,
]

private let snipeLockScreenFamilies: [WidgetFamily] = [
    .accessoryCircular,
    .accessoryRectangular,
    .accessoryInline
]

private let snipeSupportedFamilies: [WidgetFamily] = snipeHomeScreenFamilies + snipeLockScreenFamilies

private func snipeWidgetView(entry: SnipeWidgetEntry) -> some View {
    SnipeConfigurableWidgetView(entry: entry)
        .containerBackground(for: .widget) { SnipeWidgetBackground() }
}

struct SnipeOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.overview, provider: SnipeStaticTimelineProvider(displayMode: .overview)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("widget_overview_name"))
        .description(L10n.string("widget_overview_desc"))
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}

struct SnipeAuditsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.audits, provider: SnipeStaticTimelineProvider(displayMode: .audits)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("widget_audits"))
        .description(L10n.string("widget_audits_desc"))
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}

struct SnipeMaintenanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.maintenance, provider: SnipeStaticTimelineProvider(displayMode: .maintenance)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("widget_maintenance_name"))
        .description(L10n.string("widget_maintenance_desc"))
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}

struct SnipeAssetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.assets, provider: SnipeStaticTimelineProvider(displayMode: .assets)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("widget_assets_name"))
        .description(L10n.string("widget_assets_desc"))
        .supportedFamilies(snipeHomeScreenFamiliesCompact)
        .contentMarginsDisabled()
    }
}

struct SnipeStockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.stock, provider: SnipeStaticTimelineProvider(displayMode: .stock)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("widget_stock_name"))
        .description(L10n.string("widget_stock_desc"))
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}
