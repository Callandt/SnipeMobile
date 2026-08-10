import Foundation
import UIKit

/// In-memory ring buffer of privacy-scrubbed diagnostic lines, plus zip export for support.
/// Exports are intended to be safe to attach on a **public** GitHub issue.
enum AppLog {
    static func info(_ message: String, category: String = "app") {
        DebugLogStore.shared.append(message, category: category)
    }

    static func network(_ message: String) {
        info(message, category: "network")
    }
}

final class DebugLogStore: @unchecked Sendable {
    static let shared = DebugLogStore()

    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines = 2_500
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        append("Debug log started", category: "app")
    }

    func append(_ message: String, category: String = "app") {
        let stamped = "\(iso.string(from: Date())) [\(category)] \(Self.redactForPublic(message))"
        lock.lock()
        lines.append(stamped)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()
        // Intentionally no print(): Xcode console mixes system noise (CFPrefs/LaunchServices)
        // with app logs and looks like the export failed. Use the zip's app.log instead.
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    /// Start the ring buffer early so connection attempts during the session are captured.
    func startIfNeeded() {
        // Accessing shared already runs init; keep an explicit hook for app launch.
        _ = Self.shared
    }

    /// Builds a zip with diagnostics + recent log. Returns a file URL suitable for sharing.
    /// Runs a live connection check first so the zip shows whether connect succeeded/failed.
    @MainActor
    func exportZip(
        apiClient: SnipeITAPIClient,
        appChannel: AppInfo.Channel
    ) async throws -> URL {
        let stamp = Self.fileStamp()
        let extras = Self.knownPrivateStrings(from: apiClient)

        append("Building public-safe debug zip", category: "debug")
        append("Running connection check…", category: "network")

        let connectionResult: String
        if apiClient.baseURL.isEmpty || apiClient.apiToken.isEmpty {
            connectionResult = "FAILED: not configured"
            append("Connection check FAILED: not configured", category: "network")
        } else if let error = await apiClient.validateApiCredentials() {
            connectionResult = "FAILED: \(error)"
            append("Connection check FAILED: \(error)", category: "network")
        } else {
            connectionResult = "OK"
            append("Connection check OK", category: "network")
        }

        let diagnostics = Self.redactForPublic(
            diagnosticsText(
                apiClient: apiClient,
                appChannel: appChannel,
                connectionResult: connectionResult
            ),
            alsoReplacing: extras
        )
        let logText = Self.redactForPublic(
            snapshot().joined(separator: "\n") + "\n",
            alsoReplacing: extras
        )

        let files: [(name: String, data: Data)] = [
            ("diagnostics.txt", Data(diagnostics.utf8)),
            ("app.log", Data(logText.utf8))
        ]

        // Caches (not tmp) so the share sheet can reliably hand off the file.
        let exportDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugExports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        if let old = try? FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil) {
            for url in old {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let zipURL = exportDir.appendingPathComponent("SnipeMobile-Debug-\(stamp).zip")
        try SimpleZipWriter.write(files: files, to: zipURL)
        _ = try? zipURL.resourceValues(forKeys: [.fileSizeKey])
        return zipURL
    }

    @MainActor
    private func diagnosticsText(
        apiClient: SnipeITAPIClient,
        appChannel: AppInfo.Channel,
        connectionResult: String
    ) -> String {
        let device = UIDevice.current
        let url = URL(string: apiClient.baseURL)
        let scheme = url?.scheme?.lowercased() ?? "(none)"
        let host = url?.host ?? ""
        let token = KeychainSecretStore.string(for: .apiToken)

        let tokenMeta: String
        if token.isEmpty {
            tokenMeta = "missing"
        } else {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            tokenMeta = "present length=\(token.count) hasWhitespace=\(token != trimmed) hasBearerPrefix=\(token.lowercased().hasPrefix("bearer "))"
        }

        let hostKind: String
        if host.isEmpty {
            hostKind = "missing"
        } else if Self.looksLikeIPAddress(host) {
            hostKind = "ip_literal"
        } else if host.localizedCaseInsensitiveContains("localhost") {
            hostKind = "localhost"
        } else {
            hostKind = "hostname"
        }

        // Detect common paste mistakes without revealing the stored URL.
        let storedRaw = UserDefaults.standard.string(forKey: "baseURL") ?? ""
        let lowerRaw = storedRaw.lowercased()
        var urlHints: [String] = []
        if lowerRaw.contains("/api/v1") { urlHints.append("stored_value_contains_/api/v1") }
        else if lowerRaw.contains("/api") { urlHints.append("stored_value_contains_/api") }
        if lowerRaw.hasPrefix("http://") { urlHints.append("stored_scheme_http") }
        if !storedRaw.isEmpty,
           !lowerRaw.hasPrefix("http://"),
           !lowerRaw.hasPrefix("https://") {
            urlHints.append("stored_value_missing_scheme")
        }

        let lines: [String] = [
            "SnipeMobile diagnostics (public-safe)",
            "Generated: \(iso.string(from: Date()))",
            "",
            "App: \(AppInfo.versionAndBuild(channel: appChannel))",
            "iOS: \(device.systemVersion)",
            "Device: \(device.userInterfaceIdiom == .pad ? "iPad" : "iPhone") (\(Self.hardwareIdentifier))",
            "Locale: \(Locale.current.identifier)",
            "",
            "Configured: \(apiClient.isConfigured)",
            "Connection check: \(connectionResult)",
            "URL scheme: \(scheme)",
            "Host kind: \(hostKind)",
            "URL hints: \(urlHints.isEmpty ? "(none)" : urlHints.joined(separator: ", "))",
            "API token: \(tokenMeta)",
            "",
            "Cache counts:",
            "  assets=\(apiClient.assets.count)",
            "  users=\(apiClient.users.count)",
            "  accessories=\(apiClient.accessories.count)",
            "  licenses=\(apiClient.licenses.count)",
            "  consumables=\(apiClient.consumables.count)",
            "  components=\(apiClient.components.count)",
            "  locations=\(apiClient.locations.count)",
            "  hasCompletedInitialLoad=\(apiClient.hasCompletedInitialLoad)",
            "  lastError=\(Self.redactForPublic(apiClient.errorMessage ?? "(none)"))",
            "  refreshError=\(Self.redactForPublic(apiClient.refreshErrorMessage ?? "(none)"))",
            // Server messages can contain names/emails — only keep a coarse fingerprint.
            "  lastApiMessage=\(Self.summarizeServerMessage(apiClient.lastApiMessage))"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Redaction

    @MainActor
    private static func knownPrivateStrings(from apiClient: SnipeITAPIClient) -> [String] {
        var extras: [String] = []
        let base = apiClient.baseURL
        if !base.isEmpty { extras.append(base) }
        if let host = URL(string: base)?.host, !host.isEmpty {
            extras.append(host)
            // Also scrub without port if present
            if let bare = host.split(separator: ":").first.map(String.init), bare != host {
                extras.append(bare)
            }
        }
        let token = KeychainSecretStore.string(for: .apiToken)
        if token.count >= 8 { extras.append(token) }
        return extras
    }

    static func redactForPublic(_ text: String, alsoReplacing extras: [String] = []) -> String {
        var out = text

        // Explicit known secrets / host first (longest first to avoid partial leftovers).
        for extra in extras.sorted(by: { $0.count > $1.count }) where extra.count >= 3 {
            out = out.replacingOccurrences(of: extra, with: "<redacted>", options: .caseInsensitive)
        }

        // Full URLs
        out = replace(out, pattern: #"https?://[^\s\"'<>]+"#, with: "<url>")
        // Emails
        out = replace(out, pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, with: "<email>")
        // IPv4
        out = replace(out, pattern: #"\b\d{1,3}(?:\.\d{1,3}){3}\b"#, with: "<ip>")
        // IPv6 (coarse)
        out = replace(out, pattern: #"\b(?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}\b"#, with: "<ip>")
        // Bearer tokens
        out = replace(out, pattern: #"(?i)(Bearer\s+)([^\s\"']+)"#, with: "$1<redacted>")
        // Labeled secrets
        out = replace(
            out,
            pattern: #"(?i)(api[_ -]?key|token|authorization|password|secret)([\"'=\s:]+)([A-Za-z0-9._\-+/=]{8,})"#,
            with: "$1$2<redacted>"
        )
        // host=… leftovers from older log lines
        out = replace(out, pattern: #"(?i)\bhost=([^\s,]+)"#, with: "host=<redacted>")
        // JSON-ish email/name fields if a body ever leaked in
        out = replace(out, pattern: #"(?i)("(?:email|username|name|first_name|last_name|employee_num)"\s*:\s*")([^"]*)(")"#, with: "$1<redacted>$3")

        return out
    }

    /// Backward-compatible alias used by call sites.
    static func redact(_ text: String) -> String { redactForPublic(text) }

    private static func summarizeServerMessage(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "(none)" }
        let scrubbed = redactForPublic(message)
        if scrubbed.count <= 80 {
            return scrubbed
        }
        return "length=\(message.count) preview=\(scrubbed.prefix(60))…"
    }

    private static func looksLikeIPAddress(_ host: String) -> Bool {
        let v4 = host.range(of: #"^\d{1,3}(?:\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        let v6 = host.contains(":")
        return v4 || v6
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static var hardwareIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
}

/// Minimal ZIP writer (STORE / no compression) for text diagnostics.
enum SimpleZipWriter {
    static func write(files: [(name: String, data: Data)], to url: URL) throws {
        var localParts = Data()
        var central = Data()
        var offset: UInt32 = 0

        for file in files {
            let nameData = Data(file.name.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)
            let nameLen = UInt16(nameData.count)

            var local = Data()
            local.appendUInt32(0x04034b50) // local file header
            local.appendUInt16(20) // version needed
            local.appendUInt16(0) // flags
            local.appendUInt16(0) // compression = store
            local.appendUInt16(0) // mod time
            local.appendUInt16(0) // mod date
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(nameLen)
            local.appendUInt16(0) // extra len
            local.append(nameData)
            local.append(file.data)

            var cen = Data()
            cen.appendUInt32(0x02014b50) // central directory header
            cen.appendUInt16(20) // version made by
            cen.appendUInt16(20) // version needed
            cen.appendUInt16(0)
            cen.appendUInt16(0)
            cen.appendUInt16(0)
            cen.appendUInt16(0)
            cen.appendUInt32(crc)
            cen.appendUInt32(size)
            cen.appendUInt32(size)
            cen.appendUInt16(nameLen)
            cen.appendUInt16(0) // extra
            cen.appendUInt16(0) // comment
            cen.appendUInt16(0) // disk start
            cen.appendUInt16(0) // int attrs
            cen.appendUInt32(0) // ext attrs
            cen.appendUInt32(offset)
            cen.append(nameData)

            localParts.append(local)
            central.append(cen)
            offset += UInt32(local.count)
        }

        var end = Data()
        end.appendUInt32(0x06054b50)
        end.appendUInt16(0) // disk
        end.appendUInt16(0) // start disk
        end.appendUInt16(UInt16(files.count))
        end.appendUInt16(UInt16(files.count))
        end.appendUInt32(UInt32(central.count))
        end.appendUInt32(offset)
        end.appendUInt16(0) // comment

        var zip = Data()
        zip.append(localParts)
        zip.append(central)
        zip.append(end)
        try zip.write(to: url, options: .atomic)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ crcTable[idx]
        }
        return crc ^ 0xffff_ffff
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
