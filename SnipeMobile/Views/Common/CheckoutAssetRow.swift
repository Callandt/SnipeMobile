import SwiftUI

// Shared checkout pickers (user, location, asset) with matching UI.
private struct CheckoutSearchField: View {
    @Binding var searchText: String
    let placeholderKey: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.string(placeholderKey), text: $searchText)
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
    }
}


private struct CheckoutSelectionCard<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
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
}

struct CheckoutUserPickerContent: View {
    @Binding var searchText: String
    let users: [User]
    let selectedUserId: Int?
    var onSelect: (User) -> Void

    var body: some View {
        checkoutPickerContent(
            searchText: $searchText,
            placeholderKey: "search_users",
            isEmpty: users.isEmpty,
            emptyMessageKey: "no_users"
        ) {
            ForEach(users) { user in
                CheckoutUserRow(
                    user: user,
                    isSelected: selectedUserId == user.id,
                    onSelect: { onSelect(user) }
                )
            }
        }
    }
}

struct CheckoutLocationPickerContent: View {
    @Binding var searchText: String
    let locations: [Location]
    let selectedLocationId: Int?
    var onSelect: (Location) -> Void

    var body: some View {
        checkoutPickerContent(
            searchText: $searchText,
            placeholderKey: "search_locations",
            isEmpty: locations.isEmpty,
            emptyMessageKey: "no_locations"
        ) {
            ForEach(locations) { location in
                CheckoutLocationRow(
                    location: location,
                    isSelected: selectedLocationId == location.id,
                    onSelect: { onSelect(location) }
                )
            }
        }
    }
}

struct CheckoutAssetPickerContent: View {
    @Binding var searchText: String
    let assets: [Asset]
    let selectedAssetId: Int?
    var onSelect: (Asset) -> Void

    var body: some View {
        checkoutPickerContent(
            searchText: $searchText,
            placeholderKey: "search_assets",
            isEmpty: assets.isEmpty,
            emptyMessageKey: "no_assets_match"
        ) {
            ForEach(assets, id: \.id) { asset in
                CheckoutAssetRow(
                    asset: asset,
                    isSelected: selectedAssetId == asset.id,
                    onSelect: { onSelect(asset) }
                )
            }
        }
    }
}

@ViewBuilder
private func checkoutPickerContent<Items: View>(
    searchText: Binding<String>,
    placeholderKey: String,
    isEmpty: Bool,
    emptyMessageKey: String,
    @ViewBuilder items: () -> Items
) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        CheckoutSearchField(searchText: searchText, placeholderKey: placeholderKey)

        if isEmpty {
            Text(L10n.string(emptyMessageKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    items()
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 300)
        }
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    .listRowBackground(Color.clear)
}

struct CheckoutUserRow: View {
    let user: User
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            CheckoutSelectionCard(isSelected: isSelected) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray5))
                        Image(systemName: "person.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.decodedName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if !user.decodedEmail.isEmpty {
                            Text(user.decodedEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if !user.decodedLocationName.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.caption)
                                Text(user.decodedLocationName)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CheckoutLocationRow: View {
    let location: Location
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            CheckoutSelectionCard(isSelected: isSelected) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray5))
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)

                    Text(location.decodedName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CheckoutAssetRow: View {
    let asset: Asset
    let isSelected: Bool
    let onSelect: () -> Void

    private var isAssignedToLocation: Bool {
        asset.assignedTo?.isLocation == true
    }

    private var isAssignedToAsset: Bool {
        asset.assignedTo?.isAsset == true
    }

    private var titleText: String {
        if !asset.decodedModelName.isEmpty { return asset.decodedModelName }
        if !asset.decodedName.isEmpty { return asset.decodedName }
        return asset.decodedAssetTag
    }

    var body: some View {
        Button(action: onSelect) {
            CheckoutSelectionCard(isSelected: isSelected) {
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
            }
        }
        .buttonStyle(.plain)
    }

    private var assignmentIconName: String {
        if isAssignedToLocation { return "mappin.circle.fill" }
        if isAssignedToAsset { return "laptopcomputer" }
        return "person.circle.fill"
    }

    @ViewBuilder
    private var assignmentRow: some View {
        if !asset.decodedAssignedToName.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: assignmentIconName)
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

private struct DefaultCheckoutUserModifier: ViewModifier {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedUser: User?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: applyDefault)
            .onChange(of: apiClient.defaultCheckoutUser?.id) { _, _ in
                applyDefault()
            }
            .task {
                await apiClient.ensureCheckoutUserReady()
                applyDefault()
            }
    }

    private func applyDefault() {
        guard selectedUser == nil else { return }
        selectedUser = apiClient.defaultCheckoutUser
    }
}

extension View {
    func defaultCheckoutUserSelection(apiClient: SnipeITAPIClient, selectedUser: Binding<User?>) -> some View {
        modifier(DefaultCheckoutUserModifier(apiClient: apiClient, selectedUser: selectedUser))
    }
}
