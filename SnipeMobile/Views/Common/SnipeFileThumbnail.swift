import SwiftUI
import UIKit
import QuickLook

/// Thumbnail cache.
enum SnipeFileThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    static func cacheKey(objectType: String, objectId: Int, fileId: Int) -> String {
        "\(objectType.lowercased()):\(objectId):\(fileId)"
    }
}

/// Authenticated file thumbnail.
struct SnipeFileThumbnail: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let objectType: String
    let objectId: Int
    let fileId: Int
    var filename: String = ""
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?
    @State private var failed = false

    private var cacheKey: String {
        SnipeFileThumbnailCache.cacheKey(objectType: objectType, objectId: objectId, fileId: fileId)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: cacheKey) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let cached = SnipeFileThumbnailCache.image(for: cacheKey) {
            image = cached
            return
        }
        failed = false
        guard let url = await apiClient.downloadObjectFile(
            objectType: objectType,
            objectId: objectId,
            fileId: fileId,
            preferredFilename: filename.isEmpty ? "thumb-\(fileId).jpg" : filename
        ) else {
            // Scroll/reuse cancels .task — don't treat that as a hard failure.
            if Task.isCancelled { return }
            failed = true
            return
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: url)
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let data = try? Data(contentsOf: url),
              let full = UIImage(data: data) else {
            if !Task.isCancelled { failed = true }
            return
        }
        let thumb = full.snipeThumbnail(maxDimension: max(size * 3, 180))
        SnipeFileThumbnailCache.store(thumb, for: cacheKey)
        image = thumb
    }
}

/// File preview sheet (Done + share).
struct SnipeFilePreviewSheet: View {
    let url: URL
    var title: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            SnipeFileQuickLook(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title ?? url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("done")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.string("download_file"))
                    }
                }
        }
        .sheet(isPresented: $showShareSheet) {
            SnipeFileShareSheet(items: [url])
        }
    }
}

private struct SnipeFileQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

private struct SnipeFileShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension UIImage {
    func snipeThumbnail(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
