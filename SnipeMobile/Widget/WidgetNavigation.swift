import Foundation

enum WidgetNavigation {
    static func apply(
        destination: WidgetDeepLinkDestination,
        enableAuditSubtab: Bool,
        showMaintenance: Bool,
        selectedTab: inout MainTab,
        hardwareSubtab: inout HardwareAuditSubtab,
        auditListFilter: inout AuditListFilter,
        showTodayOnlyOverride: inout Bool
    ) {
        showTodayOnlyOverride = false
        auditListFilter = .all

        switch destination {
        case .overview:
            selectedTab = .hardware
            hardwareSubtab = .all
        case .audits:
            selectedTab = .hardware
            hardwareSubtab = enableAuditSubtab ? .audit : .all
        case .maintenance:
            selectedTab = .hardware
            hardwareSubtab = showMaintenance ? .maintenance : .all
        case .assets:
            selectedTab = .hardware
            hardwareSubtab = .all
        case .stock:
            selectedTab = .stock
            hardwareSubtab = .all
        }
    }
}
