import SwiftUI

struct LicenseCardView: View {
    let license: License
    var useExplicitBackground: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    private var seatsLine: String? {
        let total = license.seats
        let free = license.freeSeatsCount ?? license.remaining
        if let total, let free {
            return String(format: L10n.string("license_seats_summary"), free, total)
        }
        if let total {
            return String(format: L10n.string("license_seats_total"), total)
        }
        return nil
    }

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
                    if let seatsLine {
                        Text(seatsLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let expiration = license.expirationDate?.formatted, !expiration.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.string("expires"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(expiration)
                            .font(.caption)
                            .fontWeight(.medium)
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
