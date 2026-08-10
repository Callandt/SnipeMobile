import SwiftUI

struct MaintenanceTab: View {
    let assetId: Int
    @ObservedObject var apiClient: SnipeITAPIClient

    @State private var records: [AssetMaintenance] = []
    @State private var isLoading = false
    @State private var fetchError: String? = nil
    @State private var showCreateSheet = false
    @State private var selectedRecord: AssetMaintenance? = nil
    @State private var listVersion = 0

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L10n.string("loading_maintenance"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = fetchError {
                ContentUnavailableView(
                    L10n.string("error"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if records.isEmpty {
                ContentUnavailableView(
                    L10n.string("no_maintenance"),
                    systemImage: "wrench.and.screwdriver",
                    description: Text(L10n.string("no_maintenance_desc"))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(records) { record in
                            Button {
                                selectedRecord = record
                            } label: {
                                MaintenanceCardView(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(listVersion)
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
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.string("add_maintenance"))
            }
        }
        .task {
            await loadRecords()
        }
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            Task { await loadRecords() }
        }) {
            MaintenanceFormSheet(apiClient: apiClient, assetId: assetId, record: nil, onSave: { _ in })
        }
        .sheet(item: $selectedRecord, onDismiss: {
            Task { await loadRecords() }
        }) { record in
            MaintenanceDetailSheet(apiClient: apiClient, assetId: assetId, record: record) {
                Task { await loadRecords() }
            }
        }
    }

    private func loadRecords() async {
        if records.isEmpty {
            isLoading = true
        }
        fetchError = nil
        guard let fetched = await apiClient.fetchMaintenances(assetId: assetId) else {
            isLoading = false
            fetchError = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            return
        }
        isLoading = false
        records = fetched.sorted {
            ($0.startDate?.date ?? "") > ($1.startDate?.date ?? "")
        }
        listVersion += 1
    }
}
