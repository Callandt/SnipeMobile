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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activity.actionType.capitalized)
                    .font(.headline)
                Spacer()
                Text(activity.createdAt?.formatted ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !activity.decodedNote.isEmpty {
                Text(activity.decodedNote)
                    .font(.body)
                    .foregroundColor(.secondary)
            } else if let item = activity.item?.name, let target = activity.target?.name {
                Text("\(HTMLDecoder.decode(item)) → \(HTMLDecoder.decode(target))")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else if let item = activity.item?.name {
                Text(HTMLDecoder.decode(item))
                    .font(.body)
                    .foregroundColor(.secondary)
            } else if let target = activity.target?.name {
                Text(HTMLDecoder.decode(target))
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Text("No details available")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            // Log meta changes
            if let meta = activity.log_meta {
                ForEach(Array(meta.keys).sorted(), id: \.self) { key in
                    let change = meta[key]
                    if let new = change?.new {
                        let oldValue = (change?.old?.isEmpty ?? true) ? "NULL" : (change?.old ?? "NULL")
                        Text("\(key): \(oldValue) → \(new)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let old = change?.old {
                        Text("\(key): \(old) → NULL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            // User who performed the action
            if let user = activity.admin ?? activity.created_by {
                Text("By: \(user.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
