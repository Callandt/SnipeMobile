import Foundation

// Helper class for decoding HTML
class HTMLDecoder {
    static func decode(_ htmlString: String) -> String {
        guard !htmlString.isEmpty, let data = htmlString.data(using: .utf8) else { return htmlString }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        }
        return htmlString
    }
} 