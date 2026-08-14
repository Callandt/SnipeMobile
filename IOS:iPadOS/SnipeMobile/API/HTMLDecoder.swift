import Foundation

/// Strip HTML. Decode entities.
class HTMLDecoder {
    static func decode(_ htmlString: String) -> String {
        if htmlString.isEmpty { return htmlString }
        if !htmlString.contains(where: { $0 == "<" || $0 == "&" }) { return htmlString }
        var result = htmlString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        let entities: [String: String] = [
            "&quot;": "\"",
            "&apos;": "'",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&euro;": "€",
            "&nbsp;": " "
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        guard result.contains("&#"),
              let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) else {
            return result
        }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let full = Range(match.range(at: 0), in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let code = Int(result[numRange]),
                  let scalar = Unicode.Scalar(code) else { continue }
            result.replaceSubrange(full, with: String(scalar))
        }
        return result
    }
}
