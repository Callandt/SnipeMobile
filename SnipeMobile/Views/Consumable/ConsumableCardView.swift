import SwiftUI

struct ConsumableCardView: View {
    let consumable: Consumable
    var useExplicitBackground: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(consumable.decodedName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !consumable.decodedCategoryName.isEmpty {
                        Text(consumable.decodedCategoryName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !consumable.decodedManufacturerName.isEmpty {
                        Text(consumable.decodedManufacturerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let remaining = consumable.remaining, let qty = consumable.qty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(remaining)/\(qty)")
                            .font(.headline)
                            .foregroundStyle(remaining <= 0 ? .red : .primary)
                        Text(L10n.string("remaining"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !consumable.decodedLocationName.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "mappin.circle")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(consumable.decodedLocationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            useExplicitBackground ? Color(.secondarySystemGroupedBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}
