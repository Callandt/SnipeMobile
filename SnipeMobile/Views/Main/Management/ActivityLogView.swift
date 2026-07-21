import SwiftUI
import SafariServices

// Full activity log, same timeline look as the per-item history.
struct ActivityLogView: View {
    @ObservedObject var apiClient: SnipeITAPIClient

    @State private var activities: [Activity] = []
    @State private var isInitialLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var offset = 0
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var openSafariUrl: ActivityPdfUrl?
    @State private var localPreviewUrl: URL?
    @State private var isShowingPreview = false
    @State private var downloadingActivityId: Int?
    @State private var ephemeralNotice: EphemeralNotice?

    private let pageSize = 50

    private var filtered: [Activity] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return activities }
        return activities.filter { activity in
            if activity.decodedNote.lowercased().contains(query) { return true }
            if let item = activity.item?.name, HTMLDecoder.decode(item).lowercased().contains(query) { return true }
            if let target = activity.target?.name, HTMLDecoder.decode(target).lowercased().contains(query) { return true }
            if let filename = activity.file?.decodedFilename, filename.lowercased().contains(query) { return true }
            if activity.actionType.lowercased().contains(query) { return true }
            let user = (activity.admin ?? activity.created_by)?.name ?? ""
            return user.lowercased().contains(query)
        }
    }

    var body: some View {
        content
            .navigationTitle(L10n.string("settings_activity_log"))
            .navigationBarTitleDisplayMode(.inline)
            .task { if activities.isEmpty { await loadFirstPage() } }
            .refreshable { await reload() }
            .sheet(item: $openSafariUrl) { pdf in
                if let url = URL(string: pdf.url) {
                    ActivitySafariView(url: url)
                }
            }
            .sheet(isPresented: $isShowingPreview) {
                if let url = localPreviewUrl {
                    SnipeFilePreviewSheet(url: url)
                }
            }
            .ephemeralNotice($ephemeralNotice)
    }

    @ViewBuilder
    private var content: some View {
        if isInitialLoading && activities.isEmpty {
            ProgressView(L10n.string("loading_history"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, activities.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("mgmt_load_failed"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button(L10n.string("retry")) { Task { await loadFirstPage() } }
            }
        } else if activities.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("no_history"), systemImage: "clock.arrow.circlepath")
            }
        } else {
            ScrollView {
                timeline
            }
            .searchable(text: $searchText, prompt: Text(L10n.string("search")))
        }
    }

    private var timeline: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(filtered) { activity in
                HStack(alignment: .top, spacing: 0) {
                    Circle()
                        .fill(color(for: activity))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2.5))
                        .shadow(color: color(for: activity).opacity(0.4), radius: 3, x: 0, y: 1)
                        .padding(.top, 6)
                    card(activity: activity)
                        .padding(.leading, 16)
                        .padding(.bottom, 24)
                }
            }

            // Auto-load the next page when this sentinel scrolls into view.
            if searchText.isEmpty && canLoadMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 12)
                .onAppear { Task { await loadMore() } }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(
            GeometryReader { geo in
                let lineX = 20.0 + 6.0
                Path { path in
                    path.move(to: CGPoint(x: lineX, y: 0))
                    path.addLine(to: CGPoint(x: lineX, y: geo.size.height))
                }
                .stroke(Color.accentColor.opacity(0.25), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        )
    }

    @ViewBuilder
    private func card(activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(actionLabel(activity.actionType))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color(for: activity))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color(for: activity).opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 8)
                Text(activity.createdAt?.formatted ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Group {
                if let file = activity.file, file.isImage, let item = activity.item {
                    HStack(alignment: .top, spacing: 12) {
                        SnipeFileThumbnail(
                            apiClient: apiClient,
                            objectType: item.type,
                            objectId: item.id,
                            fileId: activity.id,
                            filename: file.decodedFilename,
                            size: 64,
                            cornerRadius: 12
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(HTMLDecoder.decode(item.name))
                                .font(.subheadline.weight(.medium))
                            Text(file.decodedFilename)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !activity.decodedNote.isEmpty {
                                Text(activity.decodedNote)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else if let item = activity.item?.name, let target = activity.target?.name {
                    Text("\(HTMLDecoder.decode(item)) → \(HTMLDecoder.decode(target))")
                        .font(.subheadline.weight(.medium))
                } else if let item = activity.item?.name {
                    Text(HTMLDecoder.decode(item)).font(.subheadline.weight(.medium))
                } else if let file = activity.file, !file.decodedFilename.isEmpty {
                    Text(file.decodedFilename).font(.subheadline.weight(.medium))
                } else if !activity.decodedNote.isEmpty {
                    Text(activity.decodedNote).font(.subheadline.weight(.medium))
                } else {
                    Text(L10n.string("no_details"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)

            if !activity.decodedNote.isEmpty,
               activity.item?.name != nil,
               !(activity.file?.isImage == true) {
                Text(activity.decodedNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 14) {
                if let user = activity.admin ?? activity.created_by {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(user.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let itemType = activity.item?.type, !itemType.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(itemType.capitalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let file = activity.file, file.url != nil || !(file.filename ?? "").isEmpty {
                    Button {
                        Task { await openAttachedFile(activity: activity, file: file) }
                    } label: {
                        HStack(spacing: 4) {
                            if downloadingActivityId == activity.id {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: file.isImage ? "photo.fill" : (file.isPDF ? "doc.richtext.fill" : "doc.fill"))
                                    .font(.caption2)
                            }
                            Text(file.isImage ? L10n.string("view_photo") : (file.isPDF ? L10n.string("view_pdf") : L10n.string("view_file")))
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .disabled(downloadingActivityId == activity.id)
                }
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
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func openAttachedFile(activity: Activity, file: ActivityFile) async {
        await MainActor.run { downloadingActivityId = activity.id }
        defer { Task { @MainActor in downloadingActivityId = nil } }

        let filename = file.decodedFilename.isEmpty ? (file.filename ?? "file") : file.decodedFilename
        let action = activity.actionType.lowercased()
        let isAcceptance = action.contains("accept") || action.contains("eula")
            || (file.url ?? "").lowercased().contains("stored-eula-file")
            || filename.lowercased().contains("accepted-eula")

        if isAcceptance {
            if let remote = file.url, !remote.isEmpty,
               let local = await apiClient.downloadFile(from: remote, preferredFilename: filename) {
                await MainActor.run {
                    localPreviewUrl = local
                    isShowingPreview = true
                }
                return
            }
            if let remote = file.url, !remote.isEmpty, file.isPDF {
                let absolute = remote.hasPrefix("http")
                    ? remote
                    : "\(apiClient.baseURL)\(remote.hasPrefix("/") ? "" : "/")\(remote)"
                await MainActor.run { openSafariUrl = ActivityPdfUrl(url: absolute) }
                return
            }
        }

        if let item = activity.item,
           let local = await apiClient.downloadObjectFile(
               objectType: item.type,
               objectId: item.id,
               fileId: activity.id,
               preferredFilename: filename
           ) {
            await MainActor.run {
                localPreviewUrl = local
                isShowingPreview = true
            }
            return
        }

        if let remote = file.url, !remote.isEmpty,
           let local = await apiClient.downloadFile(from: remote, preferredFilename: filename) {
            await MainActor.run {
                localPreviewUrl = local
                isShowingPreview = true
            }
            return
        }

        if let remote = file.url, !remote.isEmpty, file.isPDF {
            let absolute = remote.hasPrefix("http")
                ? remote
                : "\(apiClient.baseURL)\(remote.hasPrefix("/") ? "" : "/")\(remote)"
            await MainActor.run { openSafariUrl = ActivityPdfUrl(url: absolute) }
            return
        }

        await MainActor.run {
            presentEphemeralNotice(
                $ephemeralNotice,
                L10n.string("file_download_failed"),
                isError: true
            )
        }
    }

    private func color(for activity: Activity) -> Color {
        let lower = activity.actionType.lowercased()
        if lower.contains("check") && (lower.contains("out") || lower.contains("uit")) { return .green }
        if lower.contains("check") && lower.contains("in") { return .blue }
        if lower.contains("upload") { return .teal }
        if lower.contains("update") { return .orange }
        if lower.contains("create") { return .purple }
        if lower.contains("delete") { return .red }
        return .accentColor
    }

    private func actionLabel(_ type: String) -> String {
        guard L10n.isDutch else { return type.capitalized }
        let lower = type.lowercased()
        if lower.contains("check") && (lower.contains("out") || lower.contains("uit")) { return "Uitgecheckt" }
        if lower.contains("check") && lower.contains("in") { return "Ingecheckt" }
        if lower.contains("upload") && lower.contains("delete") { return "Upload verwijderd" }
        if lower.contains("upload") { return "Geüpload" }
        if lower.contains("update") { return "Bijgewerkt" }
        if lower.contains("create") { return "Aangemaakt" }
        if lower.contains("delete") { return "Verwijderd" }
        return type.capitalized
    }

    private func loadFirstPage() async {
        guard activities.isEmpty else { return }
        isInitialLoading = true
        loadError = nil
        let page = await apiClient.fetchActivityPage(limit: pageSize, offset: 0)
        isInitialLoading = false
        if let page {
            activities = page
            offset = page.count
            canLoadMore = page.count == pageSize
        } else {
            loadError = apiClient.isConfigured
                ? L10n.string("mgmt_load_failed")
                : L10n.string("settings_not_configured")
        }
    }

    private func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        let page = await apiClient.fetchActivityPage(limit: pageSize, offset: offset)
        isLoadingMore = false
        guard let page else { canLoadMore = false; return }
        let existingIds = Set(activities.map(\.id))
        let newOnes = page.filter { !existingIds.contains($0.id) }
        activities.append(contentsOf: newOnes)
        offset += page.count
        canLoadMore = page.count == pageSize
    }

    private func reload() async {
        activities = []
        offset = 0
        canLoadMore = true
        await loadFirstPage()
    }
}

private struct ActivityPdfUrl: Identifiable {
    let id = UUID()
    let url: String
}

private struct ActivitySafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
