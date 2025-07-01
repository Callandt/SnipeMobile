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
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.history.isEmpty {
                Text("No history found for this item.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(viewModel.history) { activity in
                            historyRow(activity: activity)
                        }
                    }
                    .padding()
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

    @ViewBuilder
    private func historyRow(activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // Actietype badge
                Text(activity.actionType.capitalized)
                    .font(.caption2.bold())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(Color.accentColor)
                    .clipShape(Capsule())
                Spacer()
                // Datum
                Text(activity.createdAt?.formatted ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            // Hoofdtekst
            Group {
                if !activity.decodedNote.isEmpty {
                    Text(activity.decodedNote)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                } else if let item = activity.item?.name, let target = activity.target?.name {
                    Text("\(HTMLDecoder.decode(item)) → \(HTMLDecoder.decode(target))")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                } else if let item = activity.item?.name {
                    Text(HTMLDecoder.decode(item))
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                } else if let target = activity.target?.name {
                    Text(HTMLDecoder.decode(target))
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                } else {
                    Text("No details available")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                }
            }
            // Meta-wijzigingen als chips
            if let meta = activity.log_meta {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(meta.keys).sorted(), id: \.self) { key in
                        let change = meta[key]
                        let prettyKey = prettifyFieldLabel(key)
                        if let new = change?.new {
                            let oldValue = (change?.old?.isEmpty ?? true) ? "NULL" : (change?.old ?? "NULL")
                            let newValue = new.isEmpty ? "NULL" : new
                            Text("\(prettyKey): \(oldValue) → \(newValue)")
                                .font(.caption2)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .background(Color.accentColor.opacity(0.08))
                                .foregroundColor(Color.accentColor)
                                .clipShape(Capsule())
                        } else if let old = change?.old {
                            Text("\(prettyKey): \(old) → NULL")
                                .font(.caption2)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .background(Color.accentColor.opacity(0.08))
                                .foregroundColor(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            // Gebruiker die de actie uitvoerde
            if let user = activity.admin ?? activity.created_by {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(.accentColor)
                    Text(user.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
            // Toon ontvanger bij checkout
            let isCheckout = activity.actionType.lowercased().contains("check") && activity.actionType.lowercased().contains("out")
            if isCheckout, let target = activity.target, target.type == "user" {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.accentColor)
                    Text("To: ") + Text(HTMLDecoder.decode(target.name))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
            // PDF-link tonen indien aanwezig
            if let pdfUrl = activity.file?.url, pdfUrl.lowercased().hasSuffix(".pdf") {
                Button(action: { openPdfUrl = PdfUrl(url: pdfUrl) }) {
                    Label("View PDF", systemImage: "doc.richtext")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .padding(.top, 4)
            }
            // EULA PDF-knop voor gebruikers
            if itemType == "user" {
                Button(action: {
                    guard let userId = itemId as Int? else { return }
                    print("[DEBUG] Fetching EULAs for userId: \(userId)")
                    Task {
                        let eulas = await apiClient.fetchUserEULAs(userId: userId)
                        if let eula = eulas.first, let pdfUrl = eula.url, pdfUrl.lowercased().hasSuffix(".pdf") {
                            print("[DEBUG] Download EULA PDF: \(pdfUrl)")
                            if let localUrl = await apiClient.downloadFile(from: pdfUrl) {
                                print("[DEBUG] Local EULA PDF path: \(localUrl.path)")
                                self.localPdfUrl = localUrl
                                self.isShowingPdf = true
                            } else {
                                print("[DEBUG] EULA PDF download failed")
                            }
                        } else {
                            print("[DEBUG] No EULA PDF found for user")
                        }
                    }
                }) {
                    Label("Bekijk EULA PDF", systemImage: "doc.richtext")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color(.black).opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .padding(.vertical, 2)
    }

    // Helper functie om technische veldnamen om te zetten naar gebruikersvriendelijke labels
    private func prettifyFieldLabel(_ field: String) -> String {
        let mapping: [String: String] = [
            "purchase_cost": "Purchase Cost",
            "book_value": "Book Value",
            "order_number": "Order Number",
            "asset_tag": "Asset Tag",
            "serial": "Serial Number",
            "model": "Model",
            "manufacturer": "Manufacturer",
            "category": "Category",
            "assigned_to": "Assigned To",
            "location": "Location",
            "status_label": "Status",
            "name": "Name",
            "email": "Email",
            "employee_number": "Employee Number",
            "jobtitle": "Job Title",
            // Voeg hier meer mappings toe indien gewenst
        ]
        if let pretty = mapping[field] {
            return pretty
        }
        // Custom fields: verwijder alle whitespace/underscores aan het begin én vóór 'snipeit' (case-insensitive), gevolgd door spaties/underscores/tabs aan het begin en een nummer aan het einde
        var cleaned = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: "^[\\s_]*snipeit[\\s_]*", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        // Verwijder trailing _<nummer>
        if let regex = try? NSRegularExpression(pattern: "_[0-9]+$", options: []) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        // underscores vervangen door spaties, hoofdletter aan begin
        return cleaned.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // Helper voor NL actietypes
    private func prettifyActionTypeNL(_ type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("check") && lower.contains("uit") { return "Uitgecheckt" }
        if lower.contains("check") && lower.contains("in") { return "Ingecheckt" }
        if lower.contains("update") { return "Bijgewerkt" }
        if lower.contains("create") { return "Aangemaakt" }
        if lower.contains("delete") { return "Verwijderd" }
        return type.capitalized
    }

    // SafariView wrapper voor PDF
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
