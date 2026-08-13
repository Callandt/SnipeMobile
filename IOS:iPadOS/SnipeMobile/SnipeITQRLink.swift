import Foundation

enum SnipeITQRLink: Equatable {
    case hardware(id: Int)
    case component(id: Int)
    case accessory(id: Int)
    case license(id: Int)
    case consumable(id: Int)
    case hardwareByTag(String)

    static func parse(from url: URL) -> SnipeITQRLink? {
        parse(url.absoluteString)
    }

    /// Parse Snipe-IT item URLs.
    static func parse(_ raw: String) -> SnipeITQRLink? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let query = queryString(from: text)
        let path = pathLike(from: text)
        return parse(path: path, query: query)
    }

    private static let reservedTokens: Set<String> = [
        "bytag", "create", "bulkedit", "bulkdelete", "bulkaudit", "labels",
        "audit", "requested", "clone", "restore", "import", "export",
        "quickscan", "quickadd", "checkout", "checkin", "edit", "delete",
        "view", "files", "history", "maintenances", "api", "v1",
    ]

    private static func parse(path: String, query: String?) -> SnipeITQRLink? {
        if path.localizedCaseInsensitiveContains("hardware"),
           let tag = assetTag(fromQuery: query) {
            return .hardwareByTag(tag)
        }

        let segments = path
            .split(whereSeparator: { $0 == "/" || $0 == "#" })
            .map { decode($0) }
            .filter { !$0.isEmpty }

        for index in 0..<segments.count {
            let segment = segments[index].lowercased()
            let next = index + 1 < segments.count ? segments[index + 1] : nil

            if segment == "hardware", next?.lowercased() == "bytag" {
                let tag = index + 2 < segments.count ? segments[index + 2] : nil
                if let tag, !tag.isEmpty, !isReserved(tag) {
                    return .hardwareByTag(tag)
                }
                if let queryTag = assetTag(fromQuery: query) {
                    return .hardwareByTag(queryTag)
                }
                return nil
            }

            guard let next, !next.isEmpty, !isReserved(next) else { continue }

            if segment == "ht" {
                return .hardwareByTag(next)
            }

            switch segment {
            case "hardware":
                return hardwareToken(next)
            case "components":
                if let id = Int(next) { return .component(id: id) }
            case "accessories":
                if let id = Int(next) { return .accessory(id: id) }
            case "licenses":
                if let id = Int(next) { return .license(id: id) }
            case "consumables":
                if let id = Int(next) { return .consumable(id: id) }
            default:
                continue
            }
        }
        return nil
    }

    /// Digits = id; anything else = asset tag.
    private static func hardwareToken(_ token: String) -> SnipeITQRLink {
        if let id = Int(token), String(id) == token {
            return .hardware(id: id)
        }
        return .hardwareByTag(token)
    }

    private static func isReserved(_ token: String) -> Bool {
        reservedTokens.contains(token.lowercased())
    }

    private static func pathLike(from text: String) -> String {
        var value = text
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
            if let hostEnd = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
                value = String(value[hostEnd...])
            } else {
                value = ""
            }
        }
        if let queryStart = value.firstIndex(of: "?") {
            value = String(value[..<queryStart])
        }
        return value.replacingOccurrences(of: "#", with: "/")
    }

    private static func queryString(from text: String) -> String? {
        guard let start = text.firstIndex(of: "?") else { return nil }
        var query = String(text[text.index(after: start)...])
        if let hash = query.firstIndex(of: "#") {
            query = String(query[..<hash])
        }
        return query
    }

    private static func assetTag(fromQuery query: String?) -> String? {
        guard let query, !query.isEmpty else { return nil }
        for part in query.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let name = pair[0].lowercased()
            guard name == "assettag" || name == "asset_tag" else { continue }
            let tag = decode(Substring(pair[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty { return tag }
        }
        return nil
    }

    private static func decode(_ value: Substring) -> String {
        let raw = String(value)
        return raw.removingPercentEncoding ?? raw
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
