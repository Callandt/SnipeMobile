import SwiftUI
import PhotosUI

struct AssetPhotoSection: View {
    @Binding var selectedImage: UIImage?
    @Binding var showCamera: Bool
    var existingImageURL: URL? = nil
    var removeExistingImage: Binding<Bool> = .constant(false)

    @State private var photoItem: PhotosPickerItem?

    private var showsExistingImage: Bool {
        selectedImage == nil && existingImageURL != nil && !removeExistingImage.wrappedValue
    }

    var body: some View {
        Section(header: Text(L10n.string("image"))) {
            previewRow

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(L10n.string("choose_from_library"), systemImage: "photo.on.rectangle")
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label(L10n.string("take_photo"), systemImage: "camera")
                }
            }

            if selectedImage != nil {
                Button(role: .destructive) {
                    selectedImage = nil
                    photoItem = nil
                } label: {
                    Label(L10n.string("remove_photo"), systemImage: "trash")
                }
            } else if showsExistingImage {
                Button(role: .destructive) {
                    removeExistingImage.wrappedValue = true
                } label: {
                    Label(L10n.string("remove_photo"), systemImage: "trash")
                }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run { selectedImage = uiImage }
                }
            }
        }
        .onChange(of: selectedImage) { _, newValue in
            if newValue != nil { removeExistingImage.wrappedValue = false }
        }
    }

    @ViewBuilder
    private var previewRow: some View {
        if let img = selectedImage {
            imagePreview(Image(uiImage: img))
        } else if showsExistingImage, let url = existingImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    imagePreview(image)
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
        }
    }

    private func imagePreview(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 180)
            .frame(maxWidth: .infinity)
    }
}

/// Multi-photo picker.
struct AssetPhotosSection: View {
    @Binding var selectedImages: [UIImage]
    @Binding var showCamera: Bool
    var headerTitle: String = L10n.string("photos")
    var footerText: String? = L10n.string("photos_optional_footer")

    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Section {
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button {
                                    selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                Label(L10n.string("choose_from_library"), systemImage: "photo.on.rectangle")
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label(L10n.string("take_photo"), systemImage: "camera")
                }
            }

            if !selectedImages.isEmpty {
                Button(role: .destructive) {
                    selectedImages.removeAll()
                    photoItems.removeAll()
                } label: {
                    Label(L10n.string("remove_photos"), systemImage: "trash")
                }
            }
        } header: {
            Text(headerTitle)
        } footer: {
            if let footerText {
                Text(footerText)
            }
        }
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var loaded: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        loaded.append(uiImage)
                    }
                }
                await MainActor.run {
                    selectedImages.append(contentsOf: loaded)
                    photoItems.removeAll()
                }
            }
        }
    }
}

extension View {
    func assetCameraCover(isPresented: Binding<Bool>, image: Binding<UIImage?>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            CameraPicker(image: image)
                .ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let edited = info[.editedImage] as? UIImage {
                parent.image = edited
            } else if let original = info[.originalImage] as? UIImage {
                parent.image = original
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

extension UIImage {
    func snipeJPEGUploadData(maxDimension: CGFloat = 1280, quality: CGFloat = 0.75) -> Data? {
        resizedForUpload(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    /// Base64 data URI for `image_source`.
    func snipeBase64ImageSource(maxDimension: CGFloat = 1280, quality: CGFloat = 0.75) -> String? {
        guard let data = snipeJPEGUploadData(maxDimension: maxDimension, quality: quality) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private func resizedForUpload(maxDimension: CGFloat) -> UIImage {
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
