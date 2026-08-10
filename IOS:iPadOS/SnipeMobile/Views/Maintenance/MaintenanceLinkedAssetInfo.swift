import Foundation

// asset info shown on maintenance cards and the detail sheet
struct MaintenanceLinkedAssetInfo {
    let title: String
    let detailLine: String?
    let assignee: String?

    static func resolve(record: AssetMaintenance, asset: Asset?) -> MaintenanceLinkedAssetInfo? {
        if let asset {
            return from(asset: asset)
        }
        return from(record: record)
    }

    private static func from(asset: Asset) -> MaintenanceLinkedAssetInfo? {
        let model = asset.decodedModelName
        let name = asset.decodedName
        let tag = asset.decodedAssetTag

        let title: String
        if !model.isEmpty {
            title = model
        } else if !name.isEmpty {
            title = name
        } else if !tag.isEmpty {
            title = tag
        } else {
            return nil
        }

        var details: [String] = []
        if !tag.isEmpty, title != tag {
            details.append(String(format: L10n.string("tag_label"), tag))
        }
        if !name.isEmpty, !model.isEmpty, name != model, title != name {
            details.append(name)
        }

        let assignee = asset.assignedTo != nil && !asset.decodedAssignedToName.isEmpty
            ? asset.decodedAssignedToName
            : nil

        return MaintenanceLinkedAssetInfo(
            title: title,
            detailLine: details.isEmpty ? nil : details.joined(separator: " · "),
            assignee: assignee
        )
    }

    private static func from(record: AssetMaintenance) -> MaintenanceLinkedAssetInfo? {
        let tag = record.assetTag.flatMap { $0.isEmpty ? nil : HTMLDecoder.decode($0) }
        let apiName = record.assetName.map { HTMLDecoder.decode($0) }.flatMap { $0.isEmpty ? nil : $0 }

        switch (apiName, tag) {
        case let (name?, tag?) where name != tag:
            return MaintenanceLinkedAssetInfo(
                title: name,
                detailLine: String(format: L10n.string("tag_label"), tag),
                assignee: nil
            )
        case let (name?, _):
            return MaintenanceLinkedAssetInfo(title: name, detailLine: nil, assignee: nil)
        case let (_, tag?):
            return MaintenanceLinkedAssetInfo(title: tag, detailLine: nil, assignee: nil)
        default:
            return nil
        }
    }
}
