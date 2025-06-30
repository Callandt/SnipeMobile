    import Foundation

// Helper class for decoding HTML
class HTMLDecoder {
    static func decode(_ htmlString: String) -> String {
        // 1. Strip HTML tags
        var result = htmlString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        // 2. Decode named HTML entities
        let entities: [String: String] = [
            "&quot;": "\"",
            "&apos;": "'",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&euro;": "€",
            "&nbsp;": " ",
            // Voeg hier meer entities toe indien nodig
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        // 3. Decode numeric entities (zoals &#039;)
        let pattern = "&#(\\d+);"
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsrange = NSRange(result.startIndex..<result.endIndex, in: result)
        var offset = 0
        regex?.enumerateMatches(in: result, options: [], range: nsrange) { match, _, _ in
            guard let match = match, match.numberOfRanges == 2,
                  let range = Range(match.range(at: 0), in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let code = Int(result[numRange]),
                  let scalar = UnicodeScalar(code) else { return }
            let replacement = String(scalar)
            let start = result.distance(from: result.startIndex, to: range.lowerBound) + offset
            let end = result.distance(from: result.startIndex, to: range.upperBound) + offset
            result.replaceSubrange(result.index(result.startIndex, offsetBy: start)..<result.index(result.startIndex, offsetBy: end), with: replacement)
            offset += replacement.count - (end - start)
        }
        return result
    }
} 
