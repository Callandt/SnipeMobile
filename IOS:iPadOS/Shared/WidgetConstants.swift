import SwiftUI
import UIKit

enum WidgetConstants {
    static let appGroupID = "group.com.pzriho.snipemobile"
    static let snapshotFileName = "widget-snapshot.json"

    static let cardCornerRadius: CGFloat = 10

    static let pageBackground = Color(uiColor: .systemBackground)
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let separatorColor = Color(uiColor: .separator)

    static let brandColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1.0)
            : UIColor(red: 15 / 255, green: 61 / 255, blue: 102 / 255, alpha: 1.0)
    })

    static let overdueColor = Color(uiColor: .systemRed)
    static let dueTodayColor = Color(uiColor: .systemOrange)
    static let dueSoonColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemYellow
            : UIColor(red: 0.85, green: 0.65, blue: 0.0, alpha: 1.0)
    })
    static let maintenanceColor = Color(uiColor: .systemOrange)
    static let assetsColor = brandColor
    static let stockColor = Color(uiColor: .systemPurple)
}
