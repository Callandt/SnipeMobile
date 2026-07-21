import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import SafariServices

private struct LocalPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Asset files tab.
struct AssetFilesTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let assetId: Int
    var reloadToken: UUID = UUID()

    @State private var files: [AssetFile] = []
    @State private var isLoading = false
    @State private var showAddSheet = false
    @State private var previewItem: LocalPreviewItem?
    @State private var openSafariUrl: PdfUrl?
    @State private var downloadingFileId: Int?
    @State private var filePendingDelete: AssetFile?
    @State private var ephemeralNotice: EphemeralNotice?

    var body: some View {
        Group {
            if isLoading && files.isEmpty {
                ProgressView(L10n.string("loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(
                    L10n.string("no_files"),
                    systemImage: "doc",
                    description: Text(L10n.string("files_empty_desc"))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(files) { file in
                            AssetFileCardView(
                                apiClient: apiClient,
                                assetId: assetId,
                                file: file,
                                isDownloading: downloadingFileId == file.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await openFile(file) }
                            }
                            .contextMenu {
                                Button {
                                    Task { await openFile(file) }
                                } label: {
                                    Label(L10n.string("view_file"), systemImage: "eye")
                                }
                                if file.canDelete {
                                    Button(role: .destructive) {
                                        filePendingDelete = file
                                    } label: {
                                        Label(L10n.string("delete"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.string("add_files"))
            }
        }
        .task(id: "\(assetId)-\(reloadToken)") {
            await reloadFiles()
        }
        .sheet(isPresented: $showAddSheet) {
            AssetAddFilesSheet(apiClient: apiClient, assetId: assetId) {
                await reloadFiles()
            }
        }
        .sheet(item: $previewItem) { item in
            SnipeFilePreviewSheet(url: item.url)
        }
        .sheet(item: $openSafariUrl) { pdf in
            if let url = URL(string: pdf.url) {
                HistoryView.SafariView(url: url)
            }
        }
        .confirmationDialog(
            L10n.string("delete_file_confirm_title"),
            isPresented: Binding(
                get: { filePendingDelete != nil },
                set: { if !$0 { filePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("delete"), role: .destructive) {
                if let file = filePendingDelete {
                    Task { await deleteFile(file) }
                }
            }
            Button(L10n.string("cancel"), role: .cancel) {
                filePendingDelete = nil
            }
        } message: {
            Text(L10n.string("delete_file_confirm_message"))
        }
        .ephemeralNotice($ephemeralNotice)
    }

    private func reloadFiles() async {
        let showSpinner = files.isEmpty
        if showSpinner {
            await MainActor.run { isLoading = true }
        }

        async let uploads = apiClient.fetchAssetFiles(assetId: assetId)
        async let activities = apiClient.fetchActivityForItem(
            itemType: "asset",
            itemId: assetId,
            limit: 100
        )
        let uploaded = await uploads
        let acceptances = await activities.compactMap { AssetFile.acceptance(from: $0) }
        let uploadIds = Set(uploaded.map(\.id))
        let extra = acceptances.filter { !uploadIds.contains($0.id) }
        let merged = (uploaded + extra).sorted {
            ($0.createdAt?.date ?? "") > ($1.createdAt?.date ?? "")
        }
        await MainActor.run {
            files = merged
            isLoading = false
        }
    }

    private func openFile(_ file: AssetFile) async {
        await MainActor.run { downloadingFileId = file.id }
        defer { Task { @MainActor in downloadingFileId = nil } }

        let filename = file.decodedFilename.isEmpty ? "file-\(file.id).pdf" : file.decodedFilename

        // EULA / acceptance: web stored-eula URL (files API uses the wrong storage path).
        if file.isAcceptance || file.isEulaURL {
            if let remote = file.url, !remote.isEmpty,
               let local = await apiClient.downloadFile(from: remote, preferredFilename: filename) {
                await MainActor.run { previewItem = LocalPreviewItem(url: local) }
                return
            }
            if let remote = file.url, !remote.isEmpty {
                let absolute = remote.hasPrefix("http")
                    ? remote
                    : "\(apiClient.baseURL)\(remote.hasPrefix("/") ? "" : "/")\(remote)"
                await MainActor.run { openSafariUrl = PdfUrl(url: absolute) }
                return
            }
            await MainActor.run {
                presentEphemeralNotice(
                    $ephemeralNotice,
                    apiClient.lastApiMessage ?? L10n.string("file_download_failed"),
                    isError: true
                )
            }
            return
        }

        if let url = await apiClient.downloadAssetFile(
            assetId: assetId,
            fileId: file.id,
            preferredFilename: filename
        ) {
            await MainActor.run { previewItem = LocalPreviewItem(url: url) }
            return
        }

        // Fallback: file.url (some installs serve downloads there).
        if let remote = file.url, !remote.isEmpty,
           let local = await apiClient.downloadFile(from: remote, preferredFilename: filename) {
            await MainActor.run { previewItem = LocalPreviewItem(url: local) }
            return
        }

        if let remote = file.url, !remote.isEmpty, file.isPDF {
            let absolute = remote.hasPrefix("http")
                ? remote
                : "\(apiClient.baseURL)\(remote.hasPrefix("/") ? "" : "/")\(remote)"
            await MainActor.run { openSafariUrl = PdfUrl(url: absolute) }
            return
        }

        await MainActor.run {
            presentEphemeralNotice(
                $ephemeralNotice,
                apiClient.lastApiMessage ?? L10n.string("file_download_failed"),
                isError: true
            )
        }
    }

    private func deleteFile(_ file: AssetFile) async {
        await MainActor.run { filePendingDelete = nil }
        let success = await apiClient.deleteAssetFile(assetId: assetId, fileId: file.id)
        if success {
            await MainActor.run { files.removeAll { $0.id == file.id } }
        } else {
            await MainActor.run {
                presentEphemeralNotice(
                    $ephemeralNotice,
                    apiClient.lastApiMessage ?? L10n.string("file_delete_failed"),
                    isError: true
                )
            }
        }
    }
}

private struct AssetFileCardView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let assetId: Int
    let file: AssetFile
    var isDownloading: Bool = false

    private var accentColor: Color {
        if file.isAcceptance || file.isPDF { return .red }
        if file.isImage { return .blue }
        let lower = file.decodedFilename.lowercased()
        if lower.hasSuffix(".zip") || lower.hasSuffix(".rar") { return .purple }
        return .accentColor
    }

    private var titleText: String {
        let note = file.decodedNote
        return note.isEmpty ? file.shortFilename : note
    }

    private var subtitleText: String? {
        guard !file.decodedNote.isEmpty else { return nil }
        let short = file.shortFilename
        return short.isEmpty ? nil : short
    }

    private var dateText: String? {
        file.createdAt?.localizedDisplay(includeTime: true)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if file.isImage {
                SnipeFileThumbnail(
                    apiClient: apiClient,
                    objectType: "hardware",
                    objectId: assetId,
                    fileId: file.id,
                    filename: file.decodedFilename,
                    size: 52,
                    cornerRadius: 12
                )
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 52, height: 52)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let dateText {
                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let subtitleText {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        if file.isAcceptance || file.isPDF { return "doc.richtext.fill" }
        let lower = file.decodedFilename.lowercased()
        if lower.hasSuffix(".zip") || lower.hasSuffix(".rar") { return "doc.zipper" }
        if [".mp4", ".mov", ".webm", ".mp3", ".wav", ".ogg"].contains(where: { lower.hasSuffix($0) }) {
            return "film.fill"
        }
        if [".xls", ".xlsx", ".ods", ".csv"].contains(where: { lower.hasSuffix($0) }) {
            return "tablecells"
        }
        if [".doc", ".docx", ".odt", ".rtf", ".txt"].contains(where: { lower.hasSuffix($0) }) {
            return "doc.text.fill"
        }
        return "doc.fill"
    }
}

private struct PendingUploadFile: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let previewImage: UIImage?

    init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        if mimeType.hasPrefix("image/"), let image = UIImage(data: data) {
            previewImage = image.snipeThumbnail(maxDimension: 120)
        } else {
            previewImage = nil
        }
    }

    var byteCountLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var systemImage: String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") || mimeType.hasPrefix("audio/") { return "film" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("rar") { return "doc.zipper" }
        return "doc"
    }
}

private enum SnipeUploadSupport {
    /// Snipe-IT upload allowlist.
    static let allowedExtensions: Set<String> = [
        "avif", "doc", "docx", "gif", "ico", "jfif", "jpeg", "jpg", "json", "key", "lic",
        "mov", "mp3", "mp4", "odp", "ods", "odt", "ogg", "pdf", "png", "rar", "rtf",
        "svg", "txt", "wav", "webm", "webp", "xls", "xlsx", "xml", "zip"
    ]

    static var importTypes: [UTType] {
        var types: [UTType] = [
            .image, .pdf, .plainText, .rtf, .json, .xml, .spreadsheet, .presentation,
            .movie, .audio, .zip, .data, .item
        ]
        for ext in allowedExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    static func isAllowed(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return allowedExtensions.contains(ext)
    }

    static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

private struct AssetAddFilesSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let assetId: Int
    var onSuccess: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var pendingFiles: [PendingUploadFile] = []
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var showFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var ephemeralNotice: EphemeralNotice?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !pendingFiles.isEmpty {
                        ForEach(pendingFiles) { file in
                            HStack(spacing: 12) {
                                pendingFileThumbnail(file)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.filename)
                                        .lineLimit(1)
                                    Text(file.byteCountLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    pendingFiles.removeAll { $0.id == file.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label(L10n.string("choose_files"), systemImage: "folder")
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

                    if !pendingFiles.isEmpty {
                        Button(role: .destructive) {
                            pendingFiles.removeAll()
                            photoItems.removeAll()
                        } label: {
                            Label(L10n.string("remove_selected_files"), systemImage: "trash")
                        }
                    }
                } header: {
                    Text(L10n.string("files"))
                } footer: {
                    Text(L10n.string("files_upload_footer"))
                }

                Section(L10n.string("notes")) {
                    TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L10n.string("add_files"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("upload")) { upload() }
                            .disabled(pendingFiles.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .assetCameraCover(isPresented: $showCamera, image: $cameraImage)
            .onChange(of: cameraImage) { _, newValue in
                if let newValue {
                    appendImage(newValue)
                    cameraImage = nil
                }
            }
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await loadPhotoItems(newItems) }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: SnipeUploadSupport.importTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await loadFileURLs(urls) }
                case .failure(let error):
                    presentEphemeralNotice(
                        $ephemeralNotice,
                        error.localizedDescription,
                        isError: true
                    )
                }
            }
            .ephemeralNotice($ephemeralNotice)
        }
    }

    @ViewBuilder
    private func pendingFileThumbnail(_ file: PendingUploadFile) -> some View {
        if let preview = file.previewImage {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: file.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
        }
    }

    private func appendImage(_ image: UIImage) {
        guard let data = image.snipeJPEGUploadData() else { return }
        let index = pendingFiles.filter { $0.filename.hasPrefix("photo-") }.count + 1
        pendingFiles.append(
            PendingUploadFile(
                filename: "photo-\(index).jpg",
                mimeType: "image/jpeg",
                data: data
            )
        )
    }

    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        var loaded: [PendingUploadFile] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.snipeJPEGUploadData() {
                let index = pendingFiles.count + loaded.count + 1
                loaded.append(
                    PendingUploadFile(
                        filename: "photo-\(index).jpg",
                        mimeType: "image/jpeg",
                        data: jpeg
                    )
                )
            }
        }
        await MainActor.run {
            pendingFiles.append(contentsOf: loaded)
            photoItems.removeAll()
        }
    }

    private func loadFileURLs(_ urls: [URL]) async {
        var loaded: [PendingUploadFile] = []
        var rejected = 0
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let filename = url.lastPathComponent
            guard SnipeUploadSupport.isAllowed(filename: filename) else {
                rejected += 1
                continue
            }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            loaded.append(
                PendingUploadFile(
                    filename: filename,
                    mimeType: SnipeUploadSupport.mimeType(for: filename),
                    data: data
                )
            )
        }
        await MainActor.run {
            pendingFiles.append(contentsOf: loaded)
            if rejected > 0 {
                presentEphemeralNotice(
                    $ephemeralNotice,
                    L10n.string("files_type_not_allowed"),
                    isError: true
                )
            }
        }
    }

    private func upload() {
        isSaving = true
        Task {
            let payload = pendingFiles.map { ($0.filename, $0.mimeType, $0.data) }
            let success = await apiClient.uploadAssetFiles(
                assetId: assetId,
                files: payload,
                notes: notes.isEmpty ? nil : notes
            )
            await MainActor.run { isSaving = false }
            if success {
                await onSuccess?()
                await MainActor.run { dismiss() }
            } else {
                await MainActor.run {
                    presentEphemeralNotice(
                        $ephemeralNotice,
                        apiClient.lastApiMessage ?? L10n.string("file_upload_failed"),
                        isError: true
                    )
                }
            }
        }
    }
}

