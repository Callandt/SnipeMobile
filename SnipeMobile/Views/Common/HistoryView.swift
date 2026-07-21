import SwiftUI
import SafariServices

struct PdfUrl: Identifiable {
    let id = UUID()
    let url: String
}

struct HistoryView: View {
    let itemType: String
    let itemId: Int
    @ObservedObject var apiClient: SnipeITAPIClient
    @StateObject private var viewModel = HistoryViewModel()
    @State private var openSafariUrl: PdfUrl? = nil
    @State private var localPreviewUrl: URL? = nil
    @State private var isShowingPreview = false
    @State private var downloadingActivityId: Int?
    @State private var ephemeralNotice: EphemeralNotice?
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(L10n.string("loading_history"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.history.isEmpty {
                Text(L10n.string("no_history"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    timelineContent
                }
            }
        }
        .onAppear {
            if viewModel.history.isEmpty && !viewModel.isLoading {
                viewModel.fetchHistory(itemType: itemType, itemId: itemId, apiClient: apiClient)
            }
        }
        .sheet(item: $openSafariUrl) { pdf in
            if let url = URL(string: pdf.url) {
                SafariView(url: url)
            }
        }
        .sheet(isPresented: $isShowingPreview) {
            if let url = localPreviewUrl {
                SnipeFilePreviewSheet(url: url)
            }
        }
        .ephemeralNotice($ephemeralNotice)
    }

    // MARK: - Timeline
    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.history.enumerated()), id: \.element.id) { index, activity in
                timelineItem(activity: activity, isLast: index == viewModel.history.count - 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(
            // Vertical line
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
    private func timelineItem(activity: Activity, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Dot
            Circle()
                .fill(timelineColor(for: activity))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2.5)
                )
                .shadow(color: timelineColor(for: activity).opacity(0.4), radius: 3, x: 0, y: 1)
                .padding(.top, 6)

            // Card
            historyCard(activity: activity)
                .padding(.leading, 16)
                .padding(.bottom, 24)
        }
    }

    private func timelineColor(for activity: Activity) -> Color {
        let lower = activity.actionType.lowercased()
        if lower.contains("check") && (lower.contains("out") || lower.contains("uit")) { return Color.green }
        if lower.contains("check") && lower.contains("in") { return Color.blue }
        if lower.contains("upload") { return Color.teal }
        if lower.contains("update") { return Color.orange }
        if lower.contains("create") { return Color.purple }
        if lower.contains("delete") { return Color.red }
        return Color.accentColor
    }

    @ViewBuilder
    private func historyCard(activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Badge and date
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.isDutch ? prettifyActionTypeNL(activity.actionType) : activity.actionType.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(timelineColor(for: activity))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(timelineColor(for: activity).opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 8)
                Text(activity.createdAt?.formatted ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Body
            Group {
                if let file = activity.file, file.isImage {
                    HStack(alignment: .top, spacing: 12) {
                        SnipeFileThumbnail(
                            apiClient: apiClient,
                            objectType: itemType,
                            objectId: itemId,
                            fileId: activity.id,
                            filename: file.decodedFilename,
                            size: 64,
                            cornerRadius: 12
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            if !activity.decodedNote.isEmpty {
                                Text(activity.decodedNote)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                            }
                            Text(file.decodedFilename)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(activity.decodedNote.isEmpty ? .primary : .secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                } else if !activity.decodedNote.isEmpty {
                    Text(activity.decodedNote)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let file = activity.file, !file.decodedFilename.isEmpty {
                    Text(file.decodedFilename)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let item = activity.item?.name, let target = activity.target?.name {
                    Text("\(HTMLDecoder.decode(item)) → \(HTMLDecoder.decode(target))")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let item = activity.item?.name {
                    Text(HTMLDecoder.decode(item))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let target = activity.target?.name {
                    Text(HTMLDecoder.decode(target))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.string("no_details"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            // Meta changes
            if let meta = activity.log_meta, !meta.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(meta.keys).sorted(), id: \.self) { key in
                        let change = meta[key]
                        let prettyKey = prettifyFieldLabel(key)
                        if let new = change?.new {
                            let oldValue = (change?.old?.isEmpty ?? true) ? "–" : (change?.old ?? "–")
                            let newValue = new.isEmpty ? "–" : new
                            metaChangeRow("\(prettyKey): \(oldValue) → \(newValue)")
                        } else if let old = change?.old {
                            metaChangeRow("\(prettyKey): \(old) → –")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // User, target, file
            VStack(alignment: .leading, spacing: 6) {
                if let user = activity.admin ?? activity.created_by {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(user.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                let isCheckout = activity.actionType.lowercased().contains("check") && (activity.actionType.lowercased().contains("out") || activity.actionType.lowercased().contains("uit"))
                if isCheckout, let target = activity.target {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: target.type == "user" ? "person.crop.circle.badge.checkmark" : "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                        Text("\(L10n.string("history_to")): \(HTMLDecoder.decode(target.name))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metaChangeRow(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openAttachedFile(activity: Activity, file: ActivityFile) async {
        await MainActor.run { downloadingActivityId = activity.id }
        defer { Task { @MainActor in downloadingActivityId = nil } }

        let filename = file.decodedFilename.isEmpty ? (file.filename ?? "file") : file.decodedFilename
        let action = activity.actionType.lowercased()
        let isAcceptance = action.contains("accept") || action.contains("eula")
            || (file.url ?? "").lowercased().contains("stored-eula-file")
            || filename.lowercased().contains("accepted-eula")

        // Acceptance EULAs live under eula-pdfs/, not hardware files API.
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
                await MainActor.run { openSafariUrl = PdfUrl(url: absolute) }
                return
            }
        }

        // file.url is web UI; use API /…/files/{activity.id}.
        if let local = await apiClient.downloadObjectFile(
            objectType: itemType,
            objectId: itemId,
            fileId: activity.id,
            preferredFilename: filename
        ) {
            await MainActor.run {
                localPreviewUrl = local
                isShowingPreview = true
            }
            return
        }

        // Retry with activity item type/id.
        if let item = activity.item,
           (item.id != itemId || item.type.lowercased() != itemType.lowercased()),
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

        // Fallback: provided URL (EULA etc).
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
            await MainActor.run { openSafariUrl = PdfUrl(url: absolute) }
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

    private func prettifyFieldLabel(_ field: String) -> String {
        let l10nKeys: [String: String] = [
            "purchase_cost": "purchase_cost",
            "book_value": "book_value",
            "order_number": "order_number",
            "asset_tag": "asset_tag",
            "serial": "serial_number",
            "model": "model",
            "manufacturer": "manufacturer",
            "category": "category",
            "assigned_to": "assigned_to",
            "location": "location",
            "status_label": "status",
            "name": "name",
            "email": "email",
            "employee_number": "employee_number",
            "jobtitle": "job_title",
        ]
        if let key = l10nKeys[field] {
            return L10n.string(key)
        }
        // Strip snipeit prefix and trailing _number
        var cleaned = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: "^[\\s_]*snipeit[\\s_]*", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        // Trailing _digits
        if let regex = try? NSRegularExpression(pattern: "_[0-9]+$", options: []) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        // Underscores to spaces. Capitalize.
        return cleaned.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func prettifyActionTypeNL(_ type: String) -> String {
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

    // PDF in Safari
    struct SafariView: UIViewControllerRepresentable {
        let url: URL
        func makeUIViewController(context: Context) -> some UIViewController {
            let vc = SFSafariViewController(url: url)
            return vc
        }
        func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
    }
}
