import SwiftUI
import WidgetKit

enum SnipeWidgetFormat {
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "nl_NL")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Background

struct SnipeWidgetBackground: View {
    var body: some View {
        ContainerRelativeShape()
            .fill(WidgetConstants.pageBackground)
    }
}

// MARK: - Layout

struct SnipeWidgetLayout<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    @ViewBuilder let content: Content

    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                content
                if isLarge, snapshot.serverHost != nil {
                    footer
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if !isSmall {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sectionSpacing: CGFloat {
        switch family {
        case .systemSmall: 7
        case .systemLarge: 10
        default: 8
        }
    }

    private var horizontalPadding: CGFloat { isLarge ? 16 : 12 }
    private var topPadding: CGFloat { isSmall ? 12 : (isLarge ? 15 : 13) }
    private var bottomPadding: CGFloat { isSmall ? 12 : (isLarge ? 15 : 13) }

    private var footer: some View {
        Text(snapshot.serverHost ?? "")
            .lineLimit(1)
            .font(.system(size: 9))
            .foregroundStyle(WidgetConstants.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Components

struct SnipeWidgetLink<Content: View>: View {
    let destination: WidgetDeepLinkDestination?
    @ViewBuilder let content: Content

    var body: some View {
        if let destination {
            Link(destination: destination.url) { content }
        } else {
            content
        }
    }
}

struct SnipeSectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetConstants.brandColor)
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetConstants.brandColor)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }
}

struct SnipeLabeledStatStrip: View {
    let title: String
    var icon: String? = nil
    let items: [SnipeStatItem]
    var valueSize: CGFloat = 20
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            SnipeSectionHeader(title: title, icon: icon)
            SnipeStatStrip(items: items, valueSize: valueSize, compact: compact)
        }
    }
}

struct SnipeStatStrip: View {
    let items: [SnipeStatItem]
    var valueSize: CGFloat = 20
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                SnipeWidgetLink(destination: item.destination) {
                    VStack(spacing: compact ? 2 : 4) {
                        Text(SnipeWidgetFormat.count(item.value))
                            .font(.system(size: valueSize, weight: .bold, design: .rounded))
                            .foregroundStyle(WidgetConstants.primaryText)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 5, height: 5)
                            Text(item.label)
                                .font(.system(size: compact ? 8 : 9, weight: .medium))
                                .foregroundStyle(WidgetConstants.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, compact ? 7 : 10)
                }

                if index < items.count - 1 {
                    Rectangle()
                        .fill(WidgetConstants.separatorColor)
                        .frame(width: 0.5)
                        .padding(.vertical, compact ? 4 : 6)
                }
            }
        }
        .background(WidgetConstants.cardBackground, in: RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius, style: .continuous))
    }
}

struct SnipeStatItem {
    let value: Int
    let label: String
    let color: Color
    var destination: WidgetDeepLinkDestination? = nil
}

struct SnipeSmallMetricPanel: View {
    let title: String
    var icon: String? = nil
    let items: [SnipeStatItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SnipeSectionHeader(title: title, icon: icon)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    SnipeWidgetLink(destination: item.destination) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)
                            Text(item.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WidgetConstants.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(SnipeWidgetFormat.count(item.value))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(WidgetConstants.primaryText)
                                .monospacedDigit()
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                    }

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 23)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WidgetConstants.cardBackground, in: RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius, style: .continuous))
    }
}

struct SnipeFocusNumber: View {
    let value: Int
    let label: String
    let caption: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetConstants.brandColor)
                    .lineLimit(1)
            }
            Text(SnipeWidgetFormat.count(value))
                .font(.system(size: compact ? 30 : 36, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetConstants.primaryText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(WidgetConstants.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(compact ? 10 : 12)
        .background(WidgetConstants.cardBackground, in: RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius, style: .continuous))
    }
}

struct SnipeWidgetSection: View {
    let title: String
    let items: [(primary: String, secondary: String?)]
    var limit: Int = 2
    var destination: WidgetDeepLinkDestination?

    var body: some View {
        if !items.isEmpty {
            SnipeWidgetLink(destination: destination) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetConstants.secondaryText)
                        .textCase(.uppercase)
                        .padding(.bottom, 1)

                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.primary)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WidgetConstants.primaryText)
                                    .lineLimit(1)
                                if let secondary = item.secondary {
                                    Text(secondary)
                                        .font(.system(size: 10))
                                        .foregroundStyle(WidgetConstants.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)

                            if index < min(items.count, limit) - 1 {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .background(WidgetConstants.cardBackground, in: RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius, style: .continuous))
                }
            }
        }
    }
}

struct SnipeEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption2)
            .foregroundStyle(WidgetConstants.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(WidgetConstants.cardBackground, in: RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius, style: .continuous))
    }
}

struct SnipeUnconfiguredView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "link.badge.plus")
                .font(.title3)
                .foregroundStyle(WidgetConstants.brandColor)
            Text("Verbind SnipeMobile")
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Main view

struct SnipeConfigurableWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnipeWidgetEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var mode: SnipeWidgetDisplayMode { entry.displayMode }

    var body: some View {
        Group {
            if !snapshot.isConfigured {
                SnipeUnconfiguredView()
            } else if family.isAccessory {
                accessoryView
            } else {
                SnipeWidgetLayout(snapshot: snapshot) {
                    content
                }
            }
        }
        .widgetURL(deepLinkURL)
    }

    private var deepLinkURL: URL {
        WidgetDeepLinkDestination(rawValue: mode.rawValue)?.url ?? WidgetDeepLinkDestination.overview.url
    }

    private var auditStats: [SnipeStatItem] {
        [
            SnipeStatItem(value: snapshot.auditsOverdue, label: "Te laat", color: WidgetConstants.overdueColor, destination: .audits),
            SnipeStatItem(value: snapshot.auditsDueToday, label: "Vandaag", color: WidgetConstants.dueTodayColor, destination: .audits),
            SnipeStatItem(value: snapshot.auditsDueSoon, label: "Binnenkort", color: WidgetConstants.dueSoonColor, destination: .audits)
        ]
    }

    private var overviewSecondaryStats: [SnipeStatItem] {
        [
            SnipeStatItem(value: snapshot.openMaintenance, label: "Maint. open", color: WidgetConstants.maintenanceColor, destination: .maintenance),
            SnipeStatItem(value: snapshot.totalAssets, label: "Assets totaal", color: WidgetConstants.assetsColor, destination: .assets),
            SnipeStatItem(value: snapshot.lowStockItems, label: "Lage voorraad", color: WidgetConstants.stockColor, destination: .stock)
        ]
    }

    private var smallAuditStats: [SnipeStatItem] {
        [
            SnipeStatItem(value: snapshot.auditsOverdue, label: "Te laat", color: WidgetConstants.overdueColor, destination: .audits),
            SnipeStatItem(value: snapshot.auditsDueToday, label: "Vandaag", color: WidgetConstants.dueTodayColor, destination: .audits)
        ]
    }

    private var smallOtherStats: [SnipeStatItem] {
        [
            SnipeStatItem(value: snapshot.openMaintenance, label: "Maint.", color: WidgetConstants.maintenanceColor, destination: .maintenance),
            SnipeStatItem(value: snapshot.totalAssets, label: "Assets", color: WidgetConstants.assetsColor, destination: .assets)
        ]
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .overview: overviewContent
        case .audits: auditsContent
        case .maintenance: maintenanceContent
        case .assets: assetsContent
        case .stock: stockContent
        }
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewContent: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 7) {
                SnipeLabeledStatStrip(title: "Audits", icon: "checkmark.seal", items: smallAuditStats, valueSize: 17, compact: true)
                SnipeLabeledStatStrip(title: "Overig", icon: "square.grid.2x2", items: smallOtherStats, valueSize: 17, compact: true)
            }
        case .systemMedium:
            VStack(spacing: 8) {
                SnipeLabeledStatStrip(title: "Audits", icon: "checkmark.seal", items: auditStats, valueSize: 22)
                SnipeLabeledStatStrip(title: "Overig", icon: "square.grid.2x2", items: overviewSecondaryStats, valueSize: 22)
            }
        default:
            VStack(spacing: 10) {
                SnipeLabeledStatStrip(title: "Audits", icon: "checkmark.seal", items: auditStats, valueSize: 24)
                SnipeLabeledStatStrip(title: "Overig", icon: "square.grid.2x2", items: overviewSecondaryStats, valueSize: 24)
                largeListSection
            }
        }
    }

    @ViewBuilder
    private var largeListSection: some View {
        if !snapshot.topOverdueAudits.isEmpty {
            SnipeWidgetSection(
                title: "Te late audits",
                items: snapshot.topOverdueAudits.map { ($0.tag, Optional($0.name)) },
                limit: 2,
                destination: .audits
            )
        } else if !snapshot.topOpenMaintenance.isEmpty {
            SnipeWidgetSection(
                title: "Open maintenance",
                items: snapshot.topOpenMaintenance.map { ($0.title, $0.assetTag) },
                limit: 2,
                destination: .maintenance
            )
        } else if !snapshot.topLowStockItems.isEmpty {
            SnipeWidgetSection(
                title: "Lage voorraad",
                items: snapshot.topLowStockItems.map { ($0.name, "\($0.remaining) over") },
                limit: 2,
                destination: .stock
            )
        } else {
            SnipeEmptyState(message: "Geen urgente acties")
        }
    }

    // MARK: Audits

    @ViewBuilder
    private var auditsContent: some View {
        switch family {
        case .systemSmall:
            SnipeSmallMetricPanel(title: "Audits", icon: "checkmark.seal", items: auditStats)
        case .systemMedium:
            SnipeLabeledStatStrip(title: "Audits", icon: "checkmark.seal", items: auditStats, valueSize: 24)
        case .systemLarge:
            VStack(spacing: 8) {
                SnipeLabeledStatStrip(title: "Audits", icon: "checkmark.seal", items: auditStats, valueSize: 28)
                if !snapshot.topOverdueAudits.isEmpty {
                    SnipeWidgetSection(
                        title: "Te late audits",
                        items: snapshot.topOverdueAudits.map { ($0.tag, Optional($0.name)) },
                        limit: 4,
                        destination: .audits
                    )
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: Maintenance

    @ViewBuilder
    private var maintenanceContent: some View {
        switch family {
        case .systemSmall:
            SnipeFocusNumber(
                value: snapshot.openMaintenance,
                label: "Maintenance",
                caption: "Open taken",
                color: WidgetConstants.maintenanceColor,
                compact: true
            )
        case .systemMedium:
            SnipeFocusNumber(
                value: snapshot.openMaintenance,
                label: "Maintenance open",
                caption: snapshot.topOpenMaintenance.first?.title ?? "—",
                color: WidgetConstants.maintenanceColor
            )
        case .systemLarge:
            VStack(spacing: 8) {
                SnipeStatStrip(items: [
                    SnipeStatItem(value: snapshot.openMaintenance, label: "Open", color: WidgetConstants.maintenanceColor)
                ], valueSize: 28)
                SnipeWidgetSection(
                    title: "Open taken",
                    items: snapshot.topOpenMaintenance.map { ($0.title, $0.assetTag) },
                    limit: 4,
                    destination: .maintenance
                )
            }
        default:
            EmptyView()
        }
    }

    // MARK: Assets

    @ViewBuilder
    private var assetsContent: some View {
        let stats = [
            SnipeStatItem(value: snapshot.totalAssets, label: "Totaal", color: WidgetConstants.assetsColor),
            SnipeStatItem(value: snapshot.deployedAssets, label: "Uitgeg.", color: WidgetConstants.dueTodayColor),
            SnipeStatItem(value: snapshot.availableAssets, label: "Vrij", color: Color(uiColor: .systemGreen))
        ]

        switch family {
        case .systemSmall:
            SnipeFocusNumber(
                value: snapshot.totalAssets,
                label: "Assets",
                caption: "\(SnipeWidgetFormat.count(snapshot.deployedAssets)) uitgeg.",
                color: WidgetConstants.assetsColor,
                compact: true
            )
        case .systemMedium, .systemLarge:
            SnipeLabeledStatStrip(
                title: "Assets",
                icon: "laptopcomputer",
                items: stats,
                valueSize: family == .systemLarge ? 26 : 22
            )
        default:
            EmptyView()
        }
    }

    // MARK: Stock

    @ViewBuilder
    private var stockContent: some View {
        switch family {
        case .systemSmall:
            SnipeFocusNumber(
                value: snapshot.lowStockItems,
                label: "Voorraad",
                caption: "Lage voorraad",
                color: WidgetConstants.stockColor,
                compact: true
            )
        case .systemMedium:
            SnipeFocusNumber(
                value: snapshot.lowStockItems,
                label: "Lage voorraad",
                caption: "Items onder minimum",
                color: WidgetConstants.stockColor
            )
        case .systemLarge:
            VStack(spacing: 8) {
                SnipeStatStrip(items: [
                    SnipeStatItem(value: snapshot.lowStockItems, label: "Lage voorraad", color: WidgetConstants.stockColor)
                ], valueSize: 28)
                SnipeWidgetSection(
                    title: "Items",
                    items: snapshot.topLowStockItems.map { ($0.name, "\($0.remaining) over") },
                    limit: 4,
                    destination: .stock
                )
            }
        default:
            EmptyView()
        }
    }

    // MARK: Lock screen

    @ViewBuilder
    private var accessoryView: some View {
        switch family {
        case .accessoryInline:
            Text(accessoryInlineText)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(accessoryPrimaryValue)")
                        .font(.title3.bold())
                    Image(systemName: mode.icon)
                        .font(.system(size: 8))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.title).font(.caption2.weight(.semibold))
                Text(accessoryInlineText).font(.caption2).lineLimit(2)
            }
        }
    }

    private var accessoryPrimaryValue: Int {
        switch mode {
        case .overview, .audits: snapshot.auditsOverdue
        case .maintenance: snapshot.openMaintenance
        case .assets: snapshot.totalAssets
        case .stock: snapshot.lowStockItems
        }
    }

    private var accessoryInlineText: String {
        switch mode {
        case .overview: "\(snapshot.auditsOverdue) audits te laat · \(snapshot.openMaintenance) maint. open"
        case .audits: "\(snapshot.auditsOverdue) audits te laat · \(snapshot.auditsDueToday) vandaag"
        case .maintenance: "\(snapshot.openMaintenance) open"
        case .assets: "\(snapshot.totalAssets) totaal"
        case .stock: "\(snapshot.lowStockItems) lage voorraad"
        }
    }
}

private extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}
