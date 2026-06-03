import SwiftUI

struct ComponentCardView: View {
    let component: Component
    var useExplicitBackground: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(component.decodedName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !component.decodedCategoryName.isEmpty {
                        Text(component.decodedCategoryName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !component.decodedManufacturerName.isEmpty {
                        Text(component.decodedManufacturerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
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
            if !component.decodedLocationName.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "mappin.circle")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(component.decodedLocationName)
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
