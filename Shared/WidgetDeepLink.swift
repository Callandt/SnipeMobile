import Foundation

enum WidgetDeepLinkDestination: String {
    case overview
    case audits
    case maintenance
    case assets
    case stock

    var url: URL {
        URL(string: "snipemobile://widget/\(rawValue)")!
    }

    static func from(url: URL) -> WidgetDeepLinkDestination? {
        guard url.scheme?.lowercased() == "snipemobile" else { return nil }

        if url.host()?.lowercased() == "widget" {
            for component in url.pathComponents.reversed() {
                if let destination = WidgetDeepLinkDestination(rawValue: component) {
                    return destination
                }
            }
        }

        if let host = url.host(), let destination = WidgetDeepLinkDestination(rawValue: host) {
            return destination
        }

        return nil
    }
}

enum WidgetDeepLinkStore {
    private static let pendingKey = "pendingWidgetDestination"

    static func storePending(_ destination: WidgetDeepLinkDestination) {
        UserDefaults(suiteName: WidgetConstants.appGroupID)?.set(destination.rawValue, forKey: pendingKey)
    }

    static func consumePending() -> WidgetDeepLinkDestination? {
        guard let defaults = UserDefaults(suiteName: WidgetConstants.appGroupID),
              let raw = defaults.string(forKey: pendingKey)
        else { return nil }
        defaults.removeObject(forKey: pendingKey)
        return WidgetDeepLinkDestination(rawValue: raw)
    }
}
