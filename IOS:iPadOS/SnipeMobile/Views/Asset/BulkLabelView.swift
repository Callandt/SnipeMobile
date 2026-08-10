//
//  BulkLabelView.swift
//  SnipeMobile
//

import SwiftUI
import UIKit

struct BulkLabelView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAssetIds: Set<Int> = []
    @State private var showAssetPicker = false
    @State private var isGenerating = false
    @State private var labelPdfURL: URL?
    @State private var showLabelPdf = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var canGenerate: Bool { !selectedAssetIds.isEmpty && !isGenerating }

    var body: some View {
        NavigationStack {
            Form {
                AssetBulkSelectionSection(
                    apiClient: apiClient,
                    selectedAssetIds: $selectedAssetIds,
                    showPicker: $showAssetPicker,
                    showScanner: .constant(false),
                    allowsScanning: false
                )

                Section {
                    Text(L10n.string("labels_server_settings_footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .assetBulkSelectionDestinations(
                apiClient: apiClient,
                selectedAssetIds: $selectedAssetIds,
                showPicker: $showAssetPicker,
                showScanner: .constant(false)
            )
            .navigationTitle(L10n.string("generate_labels"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await generate() }
                    } label: {
                        Text(L10n.string("labels_generate_run", selectedAssetIds.count))
                            .fontWeight(.semibold)
                    }
                    .disabled(!canGenerate)
                }
            }
        }
        .overlay {
            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.string("generating_labels"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $showLabelPdf, onDismiss: { labelPdfURL = nil }) {
            if let labelPdfURL {
                LabelPdfSheet(pdfURL: labelPdfURL)
            }
        }
        .alert(L10n.string("generate_labels"), isPresented: $showErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @MainActor
    private func generate() async {
        let tags = selectedAssetIds.compactMap { id -> String? in
            guard let asset = apiClient.assets.first(where: { $0.id == id }) else { return nil }
            let tag = asset.decodedAssetTag.trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? nil : tag
        }
        guard !tags.isEmpty else {
            errorMessage = L10n.string("labels_no_asset_tags")
            showErrorAlert = true
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        if let data = await apiClient.generateAssetLabels(assetTags: tags) {
            guard let url = LabelPdfSupport.writeTemporaryPdf(data, preferredName: "labels") else {
                errorMessage = L10n.string("labels_generate_failed")
                showErrorAlert = true
                return
            }
            labelPdfURL = url
            showLabelPdf = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            errorMessage = apiClient.lastApiMessage ?? L10n.string("labels_generate_failed")
            showErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
