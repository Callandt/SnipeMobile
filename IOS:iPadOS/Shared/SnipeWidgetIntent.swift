import Foundation

enum SnipeWidgetDisplayMode: String, CaseIterable {
    case overview
    case audits
    case maintenance
    case assets
    case stock

    var title: String {
        switch self {
        case .overview: return L10n.string("widget_overview")
        case .audits: return L10n.string("widget_audits")
        case .maintenance: return L10n.string("maintenance")
        case .assets: return L10n.string("assets")
        case .stock: return L10n.string("tab_stock")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .audits: return "checkmark.seal.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .assets: return "shippingbox.fill"
        case .stock: return "exclamationmark.triangle.fill"
        }
    }
}
