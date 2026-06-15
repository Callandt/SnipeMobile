//
//  BulkAuditView.swift
//  SnipeMobile
//

import SwiftUI
import UIKit

struct BulkAuditView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    // Fires after auditing so the caller can refresh notifications.
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAssetIds: Set<Int> = []
    @State private var showAssetPicker = false
    @State private var showAssetScanner = false

    // Audit options (match the web bulk audit form).
    @State private var selectedLocationId: Int = 0
    @State private var updateLocation: Bool = false
    @State private var setNextAuditDate: Bool = false
    @State private var nextAuditDate: Date = Date()
    @State private var notes: String = ""

    @State private var isSaving: Bool = false
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private var canSave: Bool { !selectedAssetIds.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                AssetBulkSelectionSection(
                    apiClient: apiClient,
                    selectedAssetIds: $selectedAssetIds,
                    showPicker: $showAssetPicker,
                    showScanner: $showAssetScanner
                )

                Section(header: Text(L10n.string("bulk_audit_options"))) {
                    if !apiClient.locations.isEmpty {
                        Picker(L10n.string("location_optional"), selection: $selectedLocationId) {
                            Text(L10n.string("none")).tag(0)
                            ForEach(apiClient.locations, id: \.id) { location in
                                Text(location.decodedName).tag(location.id)
                            }
                        }
                        if selectedLocationId != 0 {
                            Toggle(L10n.string("bulk_audit_update_location"), isOn: $updateLocation)
                        }
                    }
                    Toggle(L10n.string("bulk_audit_set_next_audit"), isOn: $setNextAuditDate)
                    if setNextAuditDate {
                        DatePicker(
                            L10n.string("next_audit_date"),
                            selection: $nextAuditDate,
                            displayedComponents: .date
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("notes"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }
            }
            .assetBulkSelectionDestinations(
                apiClient: apiClient,
                selectedAssetIds: $selectedAssetIds,
                showPicker: $showAssetPicker,
                showScanner: $showAssetScanner
            )
            .navigationTitle(L10n.string("add_audit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(L10n.string("bulk_audit_run", selectedAssetIds.count))
                            .fontWeight(.semibold)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if apiClient.locations.isEmpty {
                Task { await apiClient.fetchLocations() }
            }
        }
        .overlay {
            if isSaving {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert(L10n.string("add_audit"), isPresented: $showResultAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    @MainActor
    private func save() async {
        guard !selectedAssetIds.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let nextStr = setNextAuditDate ? dateFormatter.string(from: nextAuditDate) : nil
        let locationIdOpt: Int? = selectedLocationId == 0 ? nil : selectedLocationId
        let noteOpt: String? = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes

        var successCount = 0
        var failedCount = 0

        for id in selectedAssetIds {
            guard let asset = apiClient.assets.first(where: { $0.id == id }) else {
                failedCount += 1
                continue
            }
            let tag = asset.decodedAssetTag
            guard !tag.isEmpty else {
                failedCount += 1
                continue
            }
            let ok = await apiClient.auditAsset(
                assetTag: tag,
                assetId: asset.id,
                locationId: locationIdOpt,
                updateLocation: updateLocation,
                nextAuditDate: nextStr,
                note: noteOpt
            )
            if ok { successCount += 1 } else { failedCount += 1 }
        }

        // Pull fresh audit dates.
        await apiClient.fetchAssets()
        onSave()

        let generator = UINotificationFeedbackGenerator()
        if failedCount == 0 {
            generator.notificationOccurred(.success)
            dismiss()
        } else {
            generator.notificationOccurred(.warning)
            resultMessage = "\(L10n.string("bulk_audit_result_success", successCount))\n\(L10n.string("bulk_audit_result_partial", failedCount))"
            showResultAlert = true
        }
    }
}
