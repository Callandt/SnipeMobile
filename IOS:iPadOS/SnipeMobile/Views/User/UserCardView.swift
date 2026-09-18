import SwiftUI

struct UserCardView: View {
    let user: User
    var useExplicitBackground: Bool = true
    @Environment(\.cardLayouts) private var cardLayouts

    private var resolved: ResolvedCardLayout {
        CardLayoutResolver.resolve(
            kind: .user,
            layout: cardLayouts.layout(for: .user),
            fields: [
                .value(CardFieldID.name, user.decodedName),
                .value(CardFieldID.firstName, user.decodedFirstName),
                .value(CardFieldID.lastName, user.decodedLastName),
                .value(CardFieldID.username, user.decodedUsername),
                .value(CardFieldID.email, user.decodedEmail),
                .labeled(CardFieldID.phone, user.decodedPhone),
                .value(CardFieldID.jobTitle, user.decodedJobtitle),
                .labeled(CardFieldID.employeeNumber, user.decodedEmployeeNumber),
                .value(CardFieldID.company, user.decodedCompanyName),
                .value(CardFieldID.location, user.decodedLocationName),
                .value(
                    CardFieldID.status,
                    user.activated.map { L10n.string($0 ? "activated" : "deactivated") } ?? ""
                ),
                .labeled(CardFieldID.groups, user.groups.map(\.decodedName).filter { !$0.isEmpty }.joined(separator: ", ")),
                .labeled(CardFieldID.notes, user.decodedNotes)
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CardListIcon(systemName: "person.circle.fill", imagePath: user.image)
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
