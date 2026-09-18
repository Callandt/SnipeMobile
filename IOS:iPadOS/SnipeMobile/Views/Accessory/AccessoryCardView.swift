import SwiftUI

struct AccessoryCardView: View {
    let accessory: Accessory
    var useExplicitBackground: Bool = true
    @Environment(\.cardLayouts) private var cardLayouts

    private var resolved: ResolvedCardLayout {
        CardLayoutResolver.resolve(
            kind: .accessory,
            layout: cardLayouts.layout(for: .accessory),
            fields: [
                .value(CardFieldID.name, accessory.decodedName),
                .value(
                    CardFieldID.tag,
                    accessory.decodedAssetTag,
                    formatted: accessory.decodedAssetTag.isEmpty ? nil : L10n.string("tag_label", accessory.decodedAssetTag)
                ),
                .labeled(CardFieldID.modelNumber, accessory.modelNumber ?? ""),
                .value(CardFieldID.status, accessory.decodedStatusLabelName),
                .value(CardFieldID.manufacturer, accessory.decodedManufacturerName),
                .value(CardFieldID.category, accessory.decodedCategoryName),
                .value(CardFieldID.supplier, HTMLDecoder.decode(accessory.supplier?.name ?? "")),
                .value(CardFieldID.company, HTMLDecoder.decode(accessory.company?.name ?? "")),
                .value(CardFieldID.assignedTo, accessory.decodedAssignedToName),
                .value(CardFieldID.location, accessory.decodedLocationName),
                .labeled(CardFieldID.purchaseDate, accessory.purchaseDate ?? ""),
                .labeled(CardFieldID.purchaseCost, accessory.purchaseCost ?? ""),
                .labeled(CardFieldID.orderNumber, accessory.orderNumber ?? ""),
                .labeled(CardFieldID.notes, accessory.decodedNotes)
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CardListIcon(systemName: "mediastick", imagePath: accessory.image)
                CardLayoutHeader(resolved: resolved)
                Spacer()
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
