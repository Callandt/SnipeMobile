import Foundation

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case admin
    case user

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .admin: return L10n.string("app_mode_admin")
        case .user: return L10n.string("app_mode_user")
        }
    }
}

enum AppModeStore {
    static let modeKey = "appMode"
    static let canRequestAssetsKey = "canRequestAssets"
    static let hasDetectedModeKey = "hasDetectedAppMode"
    static let adminCapableKey = "apiIsAdminCapable"

    /// Active UI mode.
    static var current: AppMode? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey) else { return nil }
            return AppMode(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: modeKey)
            }
            CloudSettingsStore.shared.setAppMode(newValue)
        }
    }

    /// Token can use admin features (mode switch allowed).
    static var isAdminCapable: Bool {
        get { UserDefaults.standard.bool(forKey: adminCapableKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: adminCapableKey)
            CloudSettingsStore.shared.setApiIsAdminCapable(newValue)
        }
    }

    static var canRequestAssets: Bool {
        get { UserDefaults.standard.bool(forKey: canRequestAssetsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: canRequestAssetsKey)
            CloudSettingsStore.shared.setCanRequestAssets(newValue)
        }
    }

    static var hasDetectedMode: Bool {
        get { UserDefaults.standard.bool(forKey: hasDetectedModeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hasDetectedModeKey)
            CloudSettingsStore.shared.setHasDetectedAppMode(newValue)
        }
    }

    static var isUserMode: Bool { current == .user }
    static var isAdminMode: Bool { current == .admin }

    static func clear() {
        current = nil
        canRequestAssets = false
        hasDetectedMode = false
        isAdminCapable = false
    }

    /// Clear capability after URL/token change; keep shell mode.
    static func clearForServerChange() {
        canRequestAssets = false
        isAdminCapable = false
    }

    /// Older installs stored `.admin` without the capable flag.
    static func migrateAdminCapableIfNeeded() {
        if current == .admin {
            isAdminCapable = true
        }
    }

    /// First detection sets mode; later only updates capability.
    static func applyDetection(detectedMode: AppMode, canRequestAssets: Bool) {
        let wasDetected = hasDetectedMode
        let previousMode = current
        isAdminCapable = (detectedMode == .admin)
        self.canRequestAssets = canRequestAssets
        hasDetectedMode = true

        if !wasDetected {
            current = detectedMode
        } else if !isAdminCapable {
            current = .user
        } else if previousMode == nil {
            current = detectedMode
        }
        // else keep previousMode (admin viewing as user)
    }

    static func apply(mode: AppMode, canRequestAssets: Bool) {
        applyDetection(detectedMode: mode, canRequestAssets: canRequestAssets)
        current = mode
        isAdminCapable = (mode == .admin)
    }

    static func setActiveMode(_ mode: AppMode) {
        guard mode == .admin ? isAdminCapable : true else { return }
        if mode == .admin && !isAdminCapable { return }
        current = mode
    }
}

struct AppModeCheckProgress {
    enum StepState: Equatable {
        case pending
        case running
        case success
        case failure(String?)
    }

    var connection: StepState = .pending
    var rights: StepState = .pending
    var detectedMode: AppMode?

    var isComplete: Bool {
        if case .failure = connection { return true }
        if case .failure = rights { return true }
        if case .success = connection, case .success = rights { return true }
        return false
    }

    var succeeded: Bool {
        if case .success = connection, case .success = rights { return true }
        return false
    }
}
