    import Foundation

// Helper class for decoding HTML
class HTMLDecoder {
    static func decode(_ htmlString: String) -> String {
        // 1. Strip HTML tags
        var result = htmlString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        // 2. Decode common HTML entities
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
        return result
    }
} 
