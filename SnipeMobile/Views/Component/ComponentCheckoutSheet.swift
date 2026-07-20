import SwiftUI

struct ComponentCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let component: Component
    @Binding var isPresented: Bool
    var onSuccess: (() async -> Void)? = nil

    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var assetSearchText: String = ""
    @State private var selectedAsset: Asset? = nil
    @State private var quantity: Int = 1

    private var maxQuantity: Int {
        max(1, component.remaining ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CheckoutAssetPickerContent(
                        searchText: $assetSearchText,
                        assets: filteredAssets,
                        selectedAssetId: selectedAsset?.id,
                        onSelect: { asset in
                            selectedAsset = asset
                        }
                    )
                } header: {
                    Text(L10n.string("select_asset_short"))
                }

                Section {
                    Stepper(value: $quantity, in: 1...maxQuantity) {
                        HStack {
                            Text(L10n.string("quantity"))
                            Spacer()
                            Text("\(quantity)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let remaining = component.remaining {
                        HStack {
                            Text(L10n.string("remaining"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(remaining)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.string("stock_usage"))
                }

                Section {
                    TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(L10n.string("notes"))
                }
            }
            .listStyle(.insetGrouped)
            .formStyle(.grouped)
            .scrollContentBackground(.visible)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("check_out")) { handleCheckout() }
                            .disabled(selectedAsset == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if apiClient.assets.isEmpty { Task { await apiClient.fetchAssets() } }
                quantity = min(quantity, maxQuantity)
            }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
        }
    }

    var filteredAssets: [Asset] {
        apiClient.assets
            .filter {
                assetSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedAssetTag.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedModelName.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedSerial.localizedCaseInsensitiveContains(assetSearchText)
            }
            .sorted { $0.decodedAssetTag.localizedCaseInsensitiveCompare($1.decodedAssetTag) == .orderedAscending }
    }

    func handleCheckout() {
        guard let asset = selectedAsset else { return }
        isSaving = true
        Task {
            let success = await apiClient.checkoutComponent(
                componentId: component.id,
                assetId: asset.id,
                quantity: quantity,
                note: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if success {
                await onSuccess?()
                await MainActor.run {
                    isPresented = false
                    isSaving = false
                }
            } else {
                await MainActor.run {
                    isSaving = false
                    resultMessage = apiClient.lastApiMessage ?? L10n.string("checkout_failed")
                    showResult = true
                }
            }
        }
    }
}
