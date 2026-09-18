import SwiftUI

struct ConsumableCardView: View {
    let consumable: Consumable
    var useExplicitBackground: Bool = true
    @Environment(\.cardLayouts) private var cardLayouts

    private var resolved: ResolvedCardLayout {
        CardLayoutResolver.resolve(
            kind: .consumable,
            layout: cardLayouts.layout(for: .consumable),
            fields: [
                .value(CardFieldID.name, consumable.decodedName),
                .labeled(CardFieldID.itemNo, consumable.decodedItemNo),
                .labeled(CardFieldID.modelNumber, consumable.decodedModelNumber),
                .value(CardFieldID.category, consumable.decodedCategoryName),
                .value(CardFieldID.manufacturer, consumable.decodedManufacturerName),
                .value(CardFieldID.supplier, HTMLDecoder.decode(consumable.supplier?.name ?? "")),
                .value(CardFieldID.company, consumable.decodedCompanyName),
                .value(CardFieldID.location, consumable.decodedLocationName),
                .labeled(CardFieldID.purchaseDate, consumable.purchaseDate ?? ""),
                .labeled(CardFieldID.purchaseCost, consumable.purchaseCost ?? ""),
                .labeled(CardFieldID.orderNumber, consumable.orderNumber ?? ""),
                .labeled(CardFieldID.notes, HTMLDecoder.decode(consumable.notes ?? ""))
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CardListIcon(systemName: "shippingbox", imagePath: consumable.image)
                CardLayoutHeader(resolved: resolved)
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
            CardLayoutMeta(items: resolved.meta)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            useExplicitBackground ? Color(.secondarySystemBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}
