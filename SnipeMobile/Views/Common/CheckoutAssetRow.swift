import SwiftUI

// Shared asset picker for checkout sheets.
struct CheckoutAssetPickerContent: View {
    @Binding var searchText: String
    let assets: [Asset]
    let selectedAssetId: Int?
    var onSelect: (Asset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.string("search_assets"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )

            if assets.isEmpty {
                Text(L10n.string("no_assets_match"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(assets, id: \.id) { asset in
                            CheckoutAssetRow(
                                asset: asset,
                                isSelected: selectedAssetId == asset.id,
                                onSelect: { onSelect(asset) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 300)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

struct CheckoutAssetRow: View {
    let asset: Asset
    let isSelected: Bool
    let onSelect: () -> Void

    private var isAssignedToLocation: Bool {
        asset.assignedTo?.type == "location"
    }

    private var titleText: String {
        if !asset.decodedModelName.isEmpty { return asset.decodedModelName }
        if !asset.decodedName.isEmpty { return asset.decodedName }
        return asset.decodedAssetTag
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemGray5))
                    Image(systemName: "laptopcomputer")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !asset.decodedModelName.isEmpty || !asset.decodedName.isEmpty {
                        Text(String(format: L10n.string("tag_label"), asset.decodedAssetTag))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    assignmentRow
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color(.separator).opacity(0.35), lineWidth: isSelected ? 2 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var assignmentRow: some View {
        if !asset.decodedAssignedToName.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: isAssignedToLocation ? "mappin.circle.fill" : "person.circle.fill")
                    .font(.caption)
                Text(asset.decodedAssignedToName)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                Text(L10n.string("asset_available_short"))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}
