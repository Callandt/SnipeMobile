import SwiftUI

struct LicenseCardView: View {
    let license: License
    var useExplicitBackground: Bool = true
    var showSeats: Bool = true
    @Environment(\.cardLayouts) private var cardLayouts

    private var totalSeats: Int? { license.seats }
    private var freeSeats: Int? { license.freeSeatsCount ?? license.remaining }

    private var expirationText: String {
        guard let expiration = license.expirationDate?.formatted, !expiration.isEmpty else { return "" }
        return L10n.string("expires_value", expiration)
    }

    private var resolved: ResolvedCardLayout {
        CardLayoutResolver.resolve(
            kind: .license,
            layout: cardLayouts.layout(for: .license),
            fields: [
                .value(CardFieldID.name, license.decodedName),
                .value(CardFieldID.manufacturer, license.decodedManufacturerName),
                .value(CardFieldID.category, license.decodedCategoryName),
                .labeled(CardFieldID.productKey, license.decodedProductKey),
                CardFieldContent(
                    id: CardFieldID.expiration,
                    raw: license.expirationDate?.formatted ?? "",
                    formatted: expirationText,
                    icon: CardKindSpec.icon(for: CardFieldID.expiration)
                ),
                .value(CardFieldID.licensedTo, license.decodedLicenseName),
                .value(CardFieldID.licensedEmail, license.decodedLicenseEmail),
                .date(CardFieldID.purchaseDate, license.purchaseDate),
                .labeled(CardFieldID.purchaseCost, license.purchaseCost ?? ""),
                .labeled(CardFieldID.orderNumber, license.orderNumber ?? ""),
                .value(CardFieldID.supplier, license.decodedSupplierName),
                .value(CardFieldID.company, license.decodedCompanyName),
                .yesNo(CardFieldID.reassignable, license.reassignable),
                .yesNo(CardFieldID.maintained, license.maintained),
                .labeled(CardFieldID.notes, license.decodedNotes)
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                CardLayoutHeader(resolved: resolved)
                Spacer()
                if showSeats, let total = totalSeats, let free = freeSeats {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(free)/\(total)")
                            .font(.headline)
                            .foregroundStyle(free <= 0 ? .red : .primary)
                        Text(L10n.string("license_seats_free"))
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
