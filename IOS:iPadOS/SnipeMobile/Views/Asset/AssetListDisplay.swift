import SwiftUI

enum AssetListDisplay {
    static func title(for asset: Asset, layouts: CardLayoutStore) -> String {
        AssetCardFields.resolve(asset, layouts: layouts, locationName: nil, status: nil).title
    }

    static func headingTitle(for asset: Asset) -> String {
        firstNonEmpty(asset.decodedName, asset.decodedModelName, asset.decodedAssetTag)
            ?? L10n.string("asset")
    }

    private static func firstNonEmpty(_ values: String...) -> String? {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func compactSubtitle(for asset: Asset, layouts: CardLayoutStore) -> String {
        let resolved = AssetCardFields.resolve(asset, layouts: layouts, locationName: nil, status: nil)
        return ([resolved.subtitle] + resolved.headerLines)
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
