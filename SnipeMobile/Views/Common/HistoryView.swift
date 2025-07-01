import SwiftUI

struct HistoryView: View {
    let itemType: String
    let itemId: Int
    @ObservedObject var apiClient: SnipeITAPIClient
    @StateObject private var viewModel = HistoryViewModel()

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
            let isCheckout = activity.actionType.lowercased().contains("check") && activity.actionType.lowercased().contains("uit")
            if isCheckout, let target = activity.target, target.type == "user" {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.accentColor)
                    Text("To: \(HTMLDecoder.decode(target.name))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
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
}
