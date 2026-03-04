//
//  NumberFormatHelpers.swift
//  SnipeMobile
//
//  Parses user input in any locale and outputs a string for the API (decimal point, no thousands).
//  European format (1.830,86) is always supported and yields "1830.86".
//

import Foundation

enum NumberFormatHelpers {

    /// Parses a number string (e.g. European "1.830,86" or US "1,830.86") and returns a string
    /// for the API: decimal point, no thousands (e.g. "1830.86").
    /// European: dot = thousands separator, comma = decimal → "1.830,86" → "1830.86".
    /// Returns nil if the string is empty or not a valid number.
    static func normalizeDecimalForAPI(_ value: String?) -> String? {
        guard let s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        let cleaned = s
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "'", with: "")
        // Eerst expliciet Europees formaat proberen: laatste komma = decimaal, punten = duizendtallen
        if let eu = tryEuropeanFormat(cleaned) {
            return eu
        }
        let parser = NumberFormatter()
        parser.locale = Locale.current
        parser.numberStyle = .decimal
        parser.usesGroupingSeparator = true
        guard let number = parser.number(from: cleaned)?.doubleValue else {
            return tryParseWithoutLocale(cleaned)
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: number))
    }

    /// European format: punt = duizendtallen, komma = decimaal. "1.830,86" → "1830.86".
    private static func tryEuropeanFormat(_ s: String) -> String? {
        guard let lastComma = s.lastIndex(of: ",") else { return nil }
        let beforeComma = s[..<lastComma]
        let afterComma = s[s.index(after: lastComma)...]
        let integerPart = beforeComma.replacingOccurrences(of: ".", with: "")
        guard integerPart.allSatisfy({ $0.isNumber }) else { return nil }
        guard afterComma.allSatisfy({ $0.isNumber }) else { return nil }
        let combined = "\(integerPart).\(afterComma)"
        guard Double(combined) != nil else { return nil }
        return combined
    }

    /// Fallback: treat last . or , as decimal separator, the other as thousands.
    private static func tryParseWithoutLocale(_ s: String) -> String? {
        let lastDot = s.lastIndex(of: ".")
        let lastComma = s.lastIndex(of: ",")
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
        let withoutGroup = s.filter { $0 != groupChar }
        let withDot = withoutGroup.replacingOccurrences(of: String(decimalChar), with: ".")
        if withDot.isEmpty { return nil }
        if Double(withDot) != nil { return withDot }
        return nil
    }
}
