import SwiftUI

struct ComponentCardView: View {
    let component: Component
    var useExplicitBackground: Bool = true
    @Environment(\.cardLayouts) private var cardLayouts

    private var resolved: ResolvedCardLayout {
        CardLayoutResolver.resolve(
            kind: .component,
            layout: cardLayouts.layout(for: .component),
            fields: [
                .value(CardFieldID.name, component.decodedName),
                .labeled(CardFieldID.serial, component.decodedSerial),
                .labeled(CardFieldID.modelNumber, component.decodedModelNumber),
                .value(CardFieldID.category, component.decodedCategoryName),
                .value(CardFieldID.manufacturer, component.decodedManufacturerName),
                .value(CardFieldID.supplier, HTMLDecoder.decode(component.supplier?.name ?? "")),
                .value(CardFieldID.company, component.decodedCompanyName),
                .value(CardFieldID.location, component.decodedLocationName),
                .labeled(CardFieldID.purchaseDate, component.purchaseDate ?? ""),
                .labeled(CardFieldID.purchaseCost, component.purchaseCost ?? ""),
                .labeled(CardFieldID.orderNumber, component.orderNumber ?? ""),
                .labeled(CardFieldID.notes, HTMLDecoder.decode(component.notes ?? ""))
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CardListIcon(systemName: "cpu", imagePath: component.image)
                CardLayoutHeader(resolved: resolved)
                Spacer()
                if let remaining = component.remaining, let qty = component.qty {
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
