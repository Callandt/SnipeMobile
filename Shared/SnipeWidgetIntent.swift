import AppIntents
import WidgetKit

enum SnipeWidgetDisplayMode: String, AppEnum, CaseIterable {
    case overview
    case audits
    case maintenance
    case assets
    case stock

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Weergave")

    static let caseDisplayRepresentations: [SnipeWidgetDisplayMode: DisplayRepresentation] = [
        .overview: DisplayRepresentation(
            title: LocalizedStringResource("Overzicht"),
            subtitle: LocalizedStringResource("Audits, maintenance en assets"),
            image: DisplayRepresentation.Image(systemName: "square.grid.2x2")
        ),
        .audits: DisplayRepresentation(
            title: LocalizedStringResource("Audits"),
            subtitle: LocalizedStringResource("Te laat, vandaag en binnenkort"),
            image: DisplayRepresentation.Image(systemName: "checkmark.seal")
        ),
        .maintenance: DisplayRepresentation(
            title: LocalizedStringResource("Maintenance"),
            subtitle: LocalizedStringResource("Open taken"),
            image: DisplayRepresentation.Image(systemName: "wrench.and.screwdriver")
        ),
        .assets: DisplayRepresentation(
            title: LocalizedStringResource("Assets"),
            subtitle: LocalizedStringResource("Totaal en uitgegeven"),
            image: DisplayRepresentation.Image(systemName: "shippingbox")
        ),
        .stock: DisplayRepresentation(
            title: LocalizedStringResource("Voorraad"),
            subtitle: LocalizedStringResource("Lage voorraad"),
            image: DisplayRepresentation.Image(systemName: "exclamationmark.triangle")
        )
    ]

    var title: String {
        switch self {
        case .overview: return "Overzicht"
        case .audits: return "Audits"
        case .maintenance: return "Maintenance"
        case .assets: return "Assets"
        case .stock: return "Voorraad"
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

    static func resolved(from raw: String?) -> SnipeWidgetDisplayMode {
        guard let raw, let mode = SnipeWidgetDisplayMode(rawValue: raw) else {
            return .overview
        }
        return mode
    }
}

struct SnipeWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "SnipeMobile"
    static let description = IntentDescription("Kies welke Snipe-IT informatie je op de widget wilt zien.")

    @Parameter(title: "Weergave", default: .overview)
    var displayMode: SnipeWidgetDisplayMode

    init() {
        displayMode = .overview
    }

    init(displayMode: SnipeWidgetDisplayMode) {
        self.displayMode = displayMode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Toon \(\.$displayMode)")
    }
}
