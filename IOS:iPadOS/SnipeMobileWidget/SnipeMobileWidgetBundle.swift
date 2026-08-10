import WidgetKit
import SwiftUI

@main
struct SnipeMobileWidgetBundle: WidgetBundle {
    var body: some Widget {
        SnipeOverviewWidget()
        SnipeAuditsWidget()
        SnipeMaintenanceWidget()
        SnipeAssetsWidget()
        SnipeStockWidget()
    }
}
