import SwiftUI

// Assigned/checked-out user row. Uses UserCardView when cached.
struct AssignedUserCard: View {
    let user: User?
    var fallbackName: String = ""
    var fallbackEmail: String = ""

    var body: some View {
        Group {
            if let user {
                UserCardView(user: user, useExplicitBackground: false)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fallbackName.isEmpty ? L10n.string("user") : fallbackName)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            if !fallbackEmail.isEmpty {
                                Text(fallbackEmail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

// Assigned/checked-out location row.
struct AssignedLocationCard: View {
    let location: Location

    var body: some View {
        LocationCardView(location: location, useExplicitBackground: false)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Accessory checked out to a user, location, or asset.
struct AssignedAccessoryCard: View {
    let accessory: Accessory

    var body: some View {
        AccessoryCardView(accessory: accessory, useExplicitBackground: false)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
    }
}

// License seat or user-assigned license row.
struct AssignedLicenseCard: View {
    let license: License

    var body: some View {
        LicenseCardView(license: license, useExplicitBackground: false, showSeats: false)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Consumable checked out to a user.
struct AssignedConsumableCard: View {
    let consumable: Consumable

    var body: some View {
        ConsumableCardView(consumable: consumable, useExplicitBackground: false)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Component checked out to an asset. Optional ×qty badge.
struct AssignedComponentCard: View {
    let component: Component
    var quantity: Int? = nil

    var body: some View {
        ComponentCardView(component: component, useExplicitBackground: false)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if let quantity, quantity > 0 {
                    Text("×\(quantity)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .padding(12)
                }
            }
    }
}

// Assigned/checked-out asset row. Uses AssetCardView when cached; optional ×qty badge.
struct AssignedAssetCard: View {
    let asset: Asset?
    var fallbackTitle: String = ""
    var fallbackTag: String = ""
    var fallbackAssignee: String = ""
    var quantity: Int? = nil

    var body: some View {
        Group {
            if let asset {
                AssetCardView(asset: asset, useExplicitBackground: false)
            } else {
                fallbackCard
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if let quantity, quantity > 0 {
                Text("×\(quantity)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .padding(12)
            }
        }
    }

    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(fallbackTitle.isEmpty ? L10n.string("asset") : fallbackTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !fallbackTag.isEmpty {
                        Text(String(format: L10n.string("tag_label"), fallbackTag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if !fallbackAssignee.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "person.circle")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(fallbackAssignee)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Asset-based license seat row: asset first, linked user details below.
struct LicenseSeatAssetCard: View {
    let asset: Asset?
    var fallbackTitle: String = ""
    var fallbackTag: String = ""
    var assignee: SnipeITAPIClient.LicenseSeatAssignee?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(assetTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !assetTag.isEmpty {
                        Text(String(format: L10n.string("tag_label"), assetTag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let assignee, hasAssigneeDetails(assignee) {
                VStack(alignment: .leading, spacing: 6) {
                    if !assignee.name.isEmpty {
                        assigneeRow(icon: "person.circle", text: assignee.name)
                    }
                    if !assignee.email.isEmpty {
                        assigneeRow(icon: "envelope", text: assignee.email)
                    }
                    if !assignee.company.isEmpty {
                        assigneeRow(icon: "building.2", text: assignee.company)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private var assetTitle: String {
        if let asset {
            let model = asset.decodedModelName
            if !model.isEmpty { return model }
            if !asset.decodedName.isEmpty { return asset.decodedName }
        }
        if !fallbackTitle.isEmpty { return fallbackTitle }
        return L10n.string("asset")
    }

    private var assetTag: String {
        if let asset, !asset.decodedAssetTag.isEmpty { return asset.decodedAssetTag }
        return fallbackTag
    }

    private func hasAssigneeDetails(_ assignee: SnipeITAPIClient.LicenseSeatAssignee) -> Bool {
        !assignee.name.isEmpty || !assignee.email.isEmpty || !assignee.company.isEmpty
    }

    @ViewBuilder
    private func assigneeRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .lineSpacing(2)
        }
    }
}
