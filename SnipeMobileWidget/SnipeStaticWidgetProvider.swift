import SwiftUI
import WidgetKit

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

    static let all: [String] = [
        overview, audits, maintenance, assets, stock
    ]
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
        .configurationDisplayName("Overzicht")
        .description("Audits, maintenance, assets en voorraad.")
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}

struct SnipeAuditsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.audits, provider: SnipeStaticTimelineProvider(displayMode: .audits)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName("Audits")
        .description("Te laat, vandaag en binnenkort.")
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}

struct SnipeMaintenanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.maintenance, provider: SnipeStaticTimelineProvider(displayMode: .maintenance)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName("Maintenance")
        .description("Open onderhoudstaken.")
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}

struct SnipeAssetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.assets, provider: SnipeStaticTimelineProvider(displayMode: .assets)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName("Assets")
        .description("Totaal, uitgegeven en vrij.")
        .supportedFamilies(snipeHomeScreenFamiliesCompact)
        .contentMarginsDisabled()
    }
}

struct SnipeStockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnipeWidgetKinds.stock, provider: SnipeStaticTimelineProvider(displayMode: .stock)) { entry in
            snipeWidgetView(entry: entry)
        }
        .configurationDisplayName("Voorraad")
        .description("Items met lage voorraad.")
        .supportedFamilies(snipeSupportedFamilies)
        .contentMarginsDisabled()
    }
}
