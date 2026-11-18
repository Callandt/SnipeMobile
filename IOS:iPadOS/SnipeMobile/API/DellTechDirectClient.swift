//
//  DellTechDirectClient.swift
//  SnipeMobile
//
//  Dell TechDirect. Warranty + ship date.
//

import Foundation

/// Dell TechDirect: ship date + warranty months.
struct DellWarrantyInfo {
    let shipDate: Date?
    let warrantyMonths: Int?
}

enum DellTechDirectError: Error {
    case missingCredentials
    case tokenRequestFailed(String)
    case warrantyRequestFailed(String)
    case invalidResponse
}

final class DellTechDirectClient {

    private static let tokenURL = URL(string: "https://apigtwb2c.us.dell.com/auth/oauth/v2/token")!
    private static let entitlementsURLTemplate = "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements?servicetags="

    /// OAuth2 token. Current TechDirect keys use HTTP Basic; older keys use the form body.
    private static func fetchToken(clientId: String, clientSecret: String) async throws -> String {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = try? await requestToken(clientId: id, clientSecret: secret, basicAuth: true) {
            return token
        }
        return try await requestToken(clientId: id, clientSecret: secret, basicAuth: false)
    }

    private static func requestToken(
        clientId: String,
        clientSecret: String,
        basicAuth: Bool
    ) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if basicAuth {
            let raw = "\(clientId):\(clientSecret)"
            let encoded = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
            request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        } else {
            let id = clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let secret = clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            request.httpBody = "client_id=\(id)&client_secret=\(secret)&grant_type=client_credentials"
                .data(using: .utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DellTechDirectError.tokenRequestFailed("HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 0): \(msg)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw DellTechDirectError.tokenRequestFailed("No access_token in response")
        }
        return token
    }

    /// Warranty + ship for one service tag.
    static func fetchWarrantyInfo(serviceTag: String, clientId: String, clientSecret: String) async throws -> DellWarrantyInfo {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else {
            throw DellTechDirectError.missingCredentials
        }
        let tag = serviceTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else {
            throw DellTechDirectError.warrantyRequestFailed("Empty service tag")
        }

        let token = try await fetchToken(clientId: id, clientSecret: secret)
        guard let url = URL(string: entitlementsURLTemplate + tag.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!) else {
            throw DellTechDirectError.warrantyRequestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DellTechDirectError.warrantyRequestFailed("HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 0): \(msg)")
        }

        return parseEntitlementsResponse(data: data)
    }

    /// Parse entitlements. Ship date + latest end → months.
    private static func parseEntitlementsResponse(data: Data) -> DellWarrantyInfo {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter2 = ISO8601DateFormatter()
        formatter2.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String?) -> Date? {
            guard let s = s else { return nil }
            return formatter.date(from: s) ?? formatter2.date(from: s)
        }

        var first: [String: Any]?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assets = json["assets"] as? [[String: Any]] {
            first = assets.first
        } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let f = arr.first {
            first = f
        }
        guard let asset = first else {
            return DellWarrantyInfo(shipDate: nil, warrantyMonths: nil)
        }

        let shipStr = (asset["shipDate"] ?? asset["ShipDate"]) as? String
        let shipDate = parseDate(shipStr)

        var latestEnd: Date?
        let entitlements = asset["entitlements"] as? [[String: Any]] ?? []
        for ent in entitlements {
            let endStr = (ent["endDate"] ?? ent["EndDate"]) as? String
            if let d = parseDate(endStr), latestEnd == nil || d > latestEnd! {
                latestEnd = d
            }
        }

        var warrantyMonths: Int?
        if let ship = shipDate, let end = latestEnd, end > ship {
            let months = Calendar.current.dateComponents([.month], from: ship, to: end).month ?? 0
            warrantyMonths = max(0, months)
        }
        return DellWarrantyInfo(shipDate: shipDate, warrantyMonths: warrantyMonths)
    }
}
