import CryptoKit
import Foundation
import UIKit

/// Browser OAuth login.
@MainActor
final class SnipeITOAuthService {
    static let shared = SnipeITOAuthService()

    /// Redirect for Snipe-IT's public mobile OAuth client.
    static let redirectScheme = "com.grokability.snipeitmobile"
    static let redirectURI = "com.grokability.snipeitmobile://home"

    enum Discovery {
        case oauth(clientId: String)
        case unavailable
        case unreachable
    }

    struct LoginResult {
        let baseURL: String
        let token: String
    }

    enum ServiceError: LocalizedError, Equatable {
        case invalidURL
        case cancelled
        case missingCode
        case stateMismatch
        case tokenExchangeFailed
        case oauthUnavailable
        case connectionFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return L10n.string("api_validate_invalid_url")
            case .cancelled:
                return L10n.string("login_cancelled")
            case .missingCode, .stateMismatch, .tokenExchangeFailed:
                return L10n.string("login_failed")
            case .oauthUnavailable:
                return L10n.string("login_oauth_unavailable")
            case .connectionFailed:
                return L10n.string("login_connection_error")
            }
        }
    }

    static func normalizeBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return trimmed }

        let lower = trimmed.lowercased()
        if !lower.hasPrefix("http://"), !lower.hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }

        let pathSuffixes = [
            "/index.php/account/api",
            "/account/api",
            "/index.php/api/v1",
            "/index.php/api",
            "/api/v1",
            "/api",
            "/index.php",
        ]
        for suffix in pathSuffixes {
            if trimmed.lowercased().hasSuffix(suffix) {
                trimmed = String(trimmed.dropLast(suffix.count))
                break
            }
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    func discover(baseURL raw: String) async -> Discovery {
        let base = Self.normalizeBaseURL(raw)
        guard let url = URL(string: "\(base)/api/v1/client"),
              url.scheme == "http" || url.scheme == "https",
              url.host != nil
        else {
            return .unreachable
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SnipeITAPIClient.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable
            }
            guard (200...299).contains(http.statusCode) else {
                AppLog.network("OAuth discover HTTP \(http.statusCode)")
                return .unavailable
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unavailable
            }
            let clientId: String?
            if let value = json["client_id"] as? String {
                clientId = value
            } else if let value = json["client_id"] as? Int {
                clientId = String(value)
            } else if let value = json["client_id"] as? NSNumber {
                clientId = value.stringValue
            } else {
                clientId = nil
            }
            guard let clientId, !clientId.isEmpty else { return .unavailable }
            AppLog.network("OAuth client discovered")
            return .oauth(clientId: clientId)
        } catch {
            AppLog.network("OAuth discover failed kind=\(SnipeITAPIClient.connectionFailureKind(from: error).rawValue)")
            return .unreachable
        }
    }

    func signIn(baseURL raw: String, clientId: String) async throws -> LoginResult {
        let base = Self.normalizeBaseURL(raw)
        guard let authorizeBase = URL(string: "\(base)/oauth/authorize") else {
            throw ServiceError.invalidURL
        }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(verifier)
        let state = Self.makeCodeVerifier()

        var components = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components?.url else { throw ServiceError.invalidURL }

        AppLog.network("OAuth browser login started")
        let callbackURL = try await startAuthSession(url: authURL)
        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let accessToken = try await exchangeCode(
            baseURL: base,
            clientId: clientId,
            code: code,
            verifier: verifier
        )
        AppLog.network("OAuth login complete")
        return LoginResult(baseURL: base, token: accessToken)
    }

    // MARK: - Private

    private func presentationWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
    }

    private func startAuthSession(url: URL) async throws -> URL {
        do {
            return try await SnipeITOAuthBrowserSession.start(
                url: url,
                scheme: Self.redirectScheme,
                window: presentationWindow()
            )
        } catch is CancellationError {
            throw ServiceError.cancelled
        } catch {
            throw ServiceError.tokenExchangeFailed
        }
    }

    private static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        var values: [String: String] = [:]
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
            ?? URLComponents(string: callbackURL.absoluteString)?.queryItems
            ?? []
        for item in items {
            if let value = item.value, values[item.name] == nil {
                values[item.name] = value
            }
        }
        if values["code"] == nil, let query = callbackURL.query {
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, values[parts[0]] == nil {
                    values[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                }
            }
        }
        if let returnedState = values["state"], returnedState != expectedState {
            throw ServiceError.stateMismatch
        }
        if let error = values["error"] {
            AppLog.network("OAuth authorize error=\(error)")
            throw ServiceError.tokenExchangeFailed
        }
        guard let code = values["code"], !code.isEmpty else {
            throw ServiceError.missingCode
        }
        return code
    }

    private func exchangeCode(
        baseURL: String,
        clientId: String,
        code: String,
        verifier: String
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SnipeITAPIClient.userAgent, forHTTPHeaderField: "User-Agent")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.connectionFailed
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            AppLog.network("OAuth token HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw ServiceError.tokenExchangeFailed
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              !token.isEmpty
        else {
            throw ServiceError.tokenExchangeFailed
        }
        return token
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
