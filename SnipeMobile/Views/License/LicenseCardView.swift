import SwiftUI

struct LicenseCardView: View {
    let license: License
    var useExplicitBackground: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    private var totalSeats: Int? { license.seats }
    private var freeSeats: Int? { license.freeSeatsCount ?? license.remaining }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(license.decodedName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !license.decodedManufacturerName.isEmpty {
                        Text(license.decodedManufacturerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let expiration = license.expirationDate?.formatted, !expiration.isEmpty {
                        Text(String(format: L10n.string("expires_value"), expiration))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let total = totalSeats, let free = freeSeats {
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

            if !license.decodedLicenseName.isEmpty || !license.decodedLicenseEmail.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !license.decodedLicenseName.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "person.circle")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(license.decodedLicenseName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    if !license.decodedLicenseEmail.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "envelope")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(license.decodedLicenseEmail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
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
