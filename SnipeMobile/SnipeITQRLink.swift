import Foundation

enum SnipeITQRLink: Equatable {
    case hardware(id: Int)
    case component(id: Int)
    case accessory(id: Int)
    case license(id: Int)
    case consumable(id: Int)
    case hardwareByTag(String)

    static func parse(from url: URL) -> SnipeITQRLink? {
        let lowerPath = url.path.lowercased()

        if lowerPath.contains("/hardware/bytag") {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            let item = components.queryItems?.first(where: {
                let name = $0.name.lowercased()
                return name == "assettag" || name == "asset_tag"
            })
            guard let tag = item?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else {
                return nil
            }
            return .hardwareByTag(tag)
        }

        let segments = url.path.split(separator: "/").map(String.init)
        for index in 0..<(segments.count - 1) {
            let segment = segments[index].lowercased()
            let next = segments[index + 1]

            if segment == "ht" {
                let tag = (next.removingPercentEncoding ?? next)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { return nil }
                return .hardwareByTag(tag)
            }

            guard let id = Int(next) else { continue }
            switch segment {
            case "hardware": return .hardware(id: id)
            case "components": return .component(id: id)
            case "accessories": return .accessory(id: id)
            case "licenses": return .license(id: id)
            case "consumables": return .consumable(id: id)
            default: continue
            }
        }
        return nil
    }

    func notFoundMessage(id: Int) -> String {
        switch self {
        case .hardware:
            return L10n.string("asset_not_found_id", String(id))
        case .component:
            return L10n.string("component_not_found_id", String(id))
        case .accessory:
            return L10n.string("accessory_not_found_id", String(id))
        case .license:
            return L10n.string("license_not_found_id", String(id))
        case .consumable:
            return L10n.string("consumable_not_found_id", String(id))
        case .hardwareByTag:
            return L10n.string("asset_not_found_id", String(id))
        }
    }
}
