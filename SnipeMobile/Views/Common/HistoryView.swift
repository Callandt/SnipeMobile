import SwiftUI
import SafariServices
import QuickLook

struct PdfUrl: Identifiable {
    let id = UUID()
    let url: String
}

struct HistoryView: View {
    let itemType: String
    let itemId: Int
    @ObservedObject var apiClient: SnipeITAPIClient
    @StateObject private var viewModel = HistoryViewModel()
    @State private var openPdfUrl: PdfUrl? = nil
    @State private var localPdfUrl: URL? = nil
    @State private var isShowingPdf = false
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
        .sheet(item: $openPdfUrl) { pdf in
            if let url = URL(string: pdf.url) {
                SafariView(url: url)
            }
        }
        .sheet(isPresented: $isShowingPdf) {
            if let url = localPdfUrl {
                PDFPreview(url: url)
            }
        }
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
                if !activity.decodedNote.isEmpty {
                    Text(activity.decodedNote)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                } else if let item = activity.item?.name, let target = activity.target?.name {
                    Text("\(HTMLDecoder.decode(item)) → \(HTMLDecoder.decode(target))")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                } else if let item = activity.item?.name {
                    Text(HTMLDecoder.decode(item))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                } else if let target = activity.target?.name {
                    Text(HTMLDecoder.decode(target))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                } else {
                    Text(L10n.string("no_details"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            // Meta chips
            if let meta = activity.log_meta, !meta.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(meta.keys).sorted(), id: \.self) { key in
                        let change = meta[key]
                        let prettyKey = prettifyFieldLabel(key)
                        if let new = change?.new {
                            let oldValue = (change?.old?.isEmpty ?? true) ? "–" : (change?.old ?? "–")
                            let newValue = new.isEmpty ? "–" : new
                            Text("\(prettyKey): \(oldValue) → \(newValue)")
                                .font(.caption2)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(.tertiarySystemFill))
                                .foregroundColor(.secondary)
                                .clipShape(Capsule())
                        } else if let old = change?.old {
                            Text("\(prettyKey): \(old) → –")
                                .font(.caption2)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(.tertiarySystemFill))
                                .foregroundColor(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // User, target, PDF
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
                let isCheckout = activity.actionType.lowercased().contains("check") && (activity.actionType.lowercased().contains("out") || activity.actionType.lowercased().contains("uit"))
                if isCheckout, let target = activity.target {
                    HStack(spacing: 4) {
                        Image(systemName: target.type == "user" ? "person.crop.circle.badge.checkmark" : "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(L10n.string("history_to")): \(HTMLDecoder.decode(target.name))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let pdfUrl = activity.file?.url, pdfUrl.lowercased().hasSuffix(".pdf") {
                    Button(action: { openPdfUrl = PdfUrl(url: pdfUrl) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.richtext.fill")
                                .font(.caption2)
                            Text(L10n.string("view_pdf"))
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                    }
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

    // Flow layout for chips
    private struct FlowLayout: Layout {
        var spacing: CGFloat = 8
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let result = arrange(proposal: proposal, subviews: subviews)
            return result.size
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let result = arrange(proposal: proposal, subviews: subviews)
            for (i, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: .unspecified)
            }
        }
        private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
            let maxWidth = proposal.width ?? .infinity
            var positions: [CGPoint] = []
            var x: CGFloat = 0, y: CGFloat = 0
            var rowHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if maxWidth != .infinity, x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            let width = maxWidth.isFinite ? maxWidth : max(0, x - spacing)
            return (CGSize(width: width, height: y + rowHeight), positions)
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

    struct PDFPreview: UIViewControllerRepresentable {
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
        class Coordinator: NSObject, QLPreviewControllerDataSource {
            let url: URL
            init(url: URL) { self.url = url }
            func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
            func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as QLPreviewItem }
        }
    }
}
