//
//  NumberFormatHelpers.swift
//  SnipeMobile
//
//  Parses user input in any locale and outputs a string for the API (decimal point, no thousands).
//

import Foundation

enum NumberFormatHelpers {

    /// Parses a number string using the user's current locale (e.g. 1.630,45 or 1,630.45 or 1 630,45)
    /// and returns a string for the API: decimal point, no thousands (e.g. "1630.45").
    /// Returns nil if the string is empty or not a valid number.
    static func normalizeDecimalForAPI(_ value: String?) -> String? {
        guard let s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        let parser = NumberFormatter()
        parser.locale = Locale.current
        parser.numberStyle = .decimal
        parser.usesGroupingSeparator = true
        guard let number = parser.number(from: s)?.doubleValue else {
            let fallback = tryParseWithoutLocale(s)
            return fallback
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: number))
    }

    /// Fallback when locale parsing fails: remove common group separators (space, apostrophe, nbsp), then treat last . or , as decimal.
    private static func tryParseWithoutLocale(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: " ", with: "")
        t = t.replacingOccurrences(of: "\u{00A0}", with: "")
        t = t.replacingOccurrences(of: "'", with: "")
        let noSpaces = t
        let lastDot = noSpaces.lastIndex(of: ".")
        let lastComma = noSpaces.lastIndex(of: ",")
        let decimalChar: Character
        let groupChar: Character
        if let ld = lastDot, let lc = lastComma {
            decimalChar = ld > lc ? "." : ","
            groupChar = decimalChar == "." ? "," : "."
        } else if lastComma != nil {
            decimalChar = ","
            groupChar = "."
        } else {
            decimalChar = "."
            groupChar = ","
        }
        let withoutGroup = noSpaces.filter { $0 != groupChar }
        let withDot = withoutGroup.replacingOccurrences(of: String(decimalChar), with: ".")
        if withDot.isEmpty { return nil }
        if Double(withDot) != nil { return withDot }
        return nil
    }
}
