import SwiftUI
import PhotosUI

struct AssetPhotoSection: View {
    @Binding var selectedImage: UIImage?
    var existingImageURL: URL? = nil
    var removeExistingImage: Binding<Bool> = .constant(false)

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

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
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage)
                .ignoresSafeArea()
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
