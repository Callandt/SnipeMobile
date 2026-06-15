//
//  AssetBulkSelection.swift
//  SnipeMobile
//

import SwiftUI
import UIKit

// MARK: - Selection section

// Pick assets from a list or scan them. Both feed the same set of IDs.
// The picker/scanner presentations live in `assetBulkSelectionDestinations`
// so they sit outside the lazy Form/List container.
struct AssetBulkSelectionSection: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedAssetIds: Set<Int>
    @Binding var showPicker: Bool
    @Binding var showScanner: Bool

    private var selectedAssets: [Asset] {
        apiClient.assets
            .filter { selectedAssetIds.contains($0.id) }
            .sorted { $0.decodedAssetTag.localizedCaseInsensitiveCompare($1.decodedAssetTag) == .orderedAscending }
    }

    var body: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                HStack {
                    Label(L10n.string("select_assets"), systemImage: "checklist")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Button {
                showScanner = true
            } label: {
                Label(L10n.string("scan_assets"), systemImage: "qrcode.viewfinder")
            }
            .foregroundStyle(.primary)
        } header: {
            HStack {
                Text(L10n.string("assets"))
                Spacer()
                Text(L10n.string("assets_selected_count", selectedAssetIds.count))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }

        if !selectedAssetIds.isEmpty {
            Section {
                ForEach(selectedAssets) { asset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                            .font(.body)
                        let subtitle = [asset.decodedAssetTag, asset.decodedName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { selectedAssets[$0].id }
                    for id in ids { selectedAssetIds.remove(id) }
                }
                Button(role: .destructive) {
                    selectedAssetIds.removeAll()
                } label: {
                    Text(L10n.string("clear_selection"))
                }
            }
        }
    }
}

extension View {
    // Attach to the Form (not a Section) so the stack always sees the destination.
    func assetBulkSelectionDestinations(
        apiClient: SnipeITAPIClient,
        selectedAssetIds: Binding<Set<Int>>,
        showPicker: Binding<Bool>,
        showScanner: Binding<Bool>
    ) -> some View {
        self
            .navigationDestination(isPresented: showPicker) {
                AssetMultiSelectView(assets: apiClient.assets, selectedAssetIds: selectedAssetIds)
            }
            .fullScreenCover(isPresented: showScanner) {
                ContinuousScannerSheet(apiClient: apiClient, selectedAssetIds: selectedAssetIds)
            }
    }
}

// MARK: - Searchable multi-select

// Searchable multi-select list.
struct AssetMultiSelectView: View {
    let assets: [Asset]
    @Binding var selectedAssetIds: Set<Int>

    @State private var searchText: String = ""

    private var filteredAssets: [Asset] {
        if searchText.isEmpty { return assets }
        let q = searchText.lowercased()
        return assets.filter {
            $0.decodedName.lowercased().contains(q) ||
            $0.decodedModelName.lowercased().contains(q) ||
            $0.decodedAssetTag.lowercased().contains(q) ||
            $0.decodedAssignedToName.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L10n.string("assets_selected_count", selectedAssetIds.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selectedAssetIds.isEmpty {
                        Button(L10n.string("clear_selection")) {
                            selectedAssetIds.removeAll()
                        }
                        .font(.subheadline)
                    }
                }
            }
            Section {
                ForEach(filteredAssets) { asset in
                    Button {
                        toggle(asset.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedAssetIds.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedAssetIds.contains(asset.id) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                let subtitle = [asset.decodedAssetTag, asset.decodedName]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · ")
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.string("search_assets")
        )
        .navigationTitle(L10n.string("select_assets"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: Int) {
        if selectedAssetIds.contains(id) {
            selectedAssetIds.remove(id)
        } else {
            selectedAssetIds.insert(id)
        }
    }
}

// MARK: - Continuous scanner sheet

// Keeps scanning and adds each resolved asset to the selection.
struct ContinuousScannerSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedAssetIds: Set<Int>

    @Environment(\.dismiss) private var dismiss

    @State private var addedAssets: [Asset] = []
    @State private var manualTag: String = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ZoomableQRScannerView(
                        completion: handleScan(_:),
                        supportedTypes: [.qr, .dataMatrix, .code39, .code128, .ean13, .upce],
                        continuous: true
                    )
                    .frame(height: 260)
                    .clipped()

                    statusBanner
                        .padding(.bottom, 12)
                }
                .frame(height: 260)

                List {
                    Section {
                        HStack {
                            TextField(L10n.string("bulk_audit_manual_placeholder"), text: $manualTag)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { addManualTag() }
                            Button(L10n.string("add")) { addManualTag() }
                                .disabled(manualTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Section {
                        if addedAssets.isEmpty {
                            Text(L10n.string("bulk_audit_empty"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(addedAssets) { asset in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                                        .font(.body)
                                    let subtitle = [asset.decodedAssetTag, asset.decodedName]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                    if !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(L10n.string("added_assets"))
                            Spacer()
                            Text("\(addedAssets.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("scan_assets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background((statusIsError ? Color.red : Color.green).opacity(0.85), in: Capsule())
        } else {
            Text(L10n.string("bulk_audit_scan_hint"))
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
        }
    }

    // MARK: Adding

    private func handleScan(_ result: Result<ScanResult, ScanError>) {
        guard case .success(let scan) = result else { return }
        Task { await add(raw: scan.string) }
    }

    private func addManualTag() {
        let value = manualTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        manualTag = ""
        Task { await add(raw: value) }
    }

    @MainActor
    private func add(raw: String) async {
        let (tag, localAsset) = derive(from: raw)
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTag.isEmpty else { return }

        var asset = localAsset
        if asset == nil {
            asset = await apiClient.fetchHardwareByTag(assetTag: cleanTag)
        }

        guard let asset else {
            show(L10n.string("asset_not_found_short", cleanTag), error: true)
            return
        }

        let label = asset.decodedAssetTag.isEmpty ? cleanTag : asset.decodedAssetTag
        if selectedAssetIds.contains(asset.id) {
            show(L10n.string("asset_already_added", label), error: true)
            return
        }

        selectedAssetIds.insert(asset.id)
        addedAssets.insert(asset, at: 0)
        show(L10n.string("asset_added", label), error: false)
    }

    private func show(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(error ? .warning : .success)
    }

    // MARK: Resolving

    private func derive(from raw: String) -> (tag: String, asset: Asset?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let asset = resolveLocally(trimmed) {
            return (asset.decodedAssetTag.isEmpty ? trimmed : asset.decodedAssetTag, asset)
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let item = comps.queryItems?.first(where: { ["asset_tag", "assettag"].contains($0.name.lowercased()) }),
               let value = item.value, !value.isEmpty {
                if let asset = resolveLocally(value) {
                    return (asset.decodedAssetTag.isEmpty ? value : asset.decodedAssetTag, asset)
                }
                return (value, nil)
            }
            if url.path.lowercased().contains("/hardware"),
               let last = url.pathComponents.last, let id = Int(last),
               let asset = apiClient.assets.first(where: { $0.id == id }) {
                return (asset.decodedAssetTag.isEmpty ? trimmed : asset.decodedAssetTag, asset)
            }
        }

        return (trimmed, nil)
    }

    private func resolveLocally(_ raw: String) -> Asset? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return apiClient.assets.first { asset in
            asset.decodedAssetTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized ||
            asset.decodedSerial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized ||
            (asset.altBarcode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") == normalized
        }
    }
}
