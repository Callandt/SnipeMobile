import CryptoKit
import SwiftUI
import UIKit

// Absolute or relative Snipe-IT image URL.
enum SnipeImageURL {
    static func resolve(baseURL: String, path: String?, cacheBuster: String? = nil) -> URL? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("/uploads/default.png") || lower.hasSuffix("/uploads/default.jpg") {
            return nil
        }

        let base: URL?
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            base = absolute
        } else if trimmed.hasPrefix("/") {
            base = URL(string: "\(baseURL)\(trimmed)")
        } else {
            base = nil
        }
        guard let base else { return nil }
        guard let cacheBuster, !cacheBuster.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "v" }
        query.append(URLQueryItem(name: "v", value: cacheBuster))
        components.queryItems = query
        return components.url ?? base
    }
}

// Memory + disk cache for card thumbnails.
enum SnipeCardPhotoCache {
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 250
        return cache
    }()
    private static var keysByPath: [String: Set<String>] = [:]
    private static let folderName = "CardPhotos"
    static let generation = Generation()

    final class Generation: ObservableObject {
        @Published var value = 0
        func bump() { value += 1 }
    }

    static func image(for url: URL) -> UIImage? {
        let key = key(for: url)
        if let cached = memory.object(forKey: key as NSString) { return cached }
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    static func store(_ image: UIImage, for url: URL) {
        let key = key(for: url)
        memory.setObject(image, forKey: key as NSString)
        keysByPath[pathKey(for: url), default: []].insert(key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = image.jpegData(compressionQuality: 0.82) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    static func invalidate(path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        let matches = keysByPath.filter { stored, _ in
            stored == trimmed || stored.hasSuffix(trimmed) || trimmed.hasSuffix(stored)
        }
        for (stored, keys) in matches {
            for key in keys {
                memory.removeObject(forKey: key as NSString)
                try? FileManager.default.removeItem(at: fileURL(for: key))
            }
            keysByPath[stored] = nil
        }
        generation.bump()
    }

    static func clear() {
        memory.removeAllObjects()
        keysByPath.removeAll()
        try? FileManager.default.removeItem(at: directory)
        generation.bump()
    }

    private static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func pathKey(for url: URL) -> String {
        url.path
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("jpg")
    }
}

// Card icon, or the item photo if that setting is on.
struct CardListIcon: View {
    let systemName: String
    var imagePath: String? = nil
    var cacheBuster: String? = nil
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 8
    var iconFont: Font = .title2
    var iconColor: Color = Color(.tertiaryLabel)
    var iconBackground: Color? = nil

    @AppStorage("showPhotosInCardList") private var showPhotosInCardList = false
    @AppStorage("baseURL") private var baseURL = ""
    @ObservedObject private var cacheGeneration = SnipeCardPhotoCache.generation
    @State private var loadedImage: UIImage?

    var body: some View {
        if let url = photoURL {
            ZStack {
                Color(.tertiarySystemFill)
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    fallbackIcon
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: "\(url.absoluteString).\(cacheGeneration.value)") {
                await loadPhoto(from: url)
            }
        } else {
            fallbackIcon
        }
    }

    private var photoURL: URL? {
        guard showPhotosInCardList else { return nil }
        return SnipeImageURL.resolve(baseURL: baseURL, path: imagePath, cacheBuster: cacheBuster)
    }

    private func loadPhoto(from url: URL) async {
        if let cached = SnipeCardPhotoCache.image(for: url) {
            loadedImage = cached
            return
        }
        loadedImage = nil
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let full = UIImage(data: data) else { return }
        if Task.isCancelled { return }
        let thumb = full.snipeThumbnail(maxDimension: 180)
        SnipeCardPhotoCache.store(thumb, for: url)
        loadedImage = thumb
    }

    private var fallbackIcon: some View {
        Image(systemName: systemName)
            .font(iconFont)
            .foregroundStyle(iconColor)
            .frame(width: size, height: size)
            .background {
                if let iconBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(iconBackground)
                }
            }
    }
}
