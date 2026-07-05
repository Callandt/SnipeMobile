import SwiftUI

/// Optional responsible-party field: compact row + searchable sheet (not an inline list).
struct MaintenanceOptionalResponsibleUserSection: View {
    @Binding var searchText: String
    @Binding var selectedUser: User?
    @Binding var wasCleared: Bool
    let users: [User]
    var isLoading: Bool

    @State private var showPicker = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            showPicker = true
        } label: {
            HStack {
                if isLoading {
                    Text(L10n.string("loading"))
                        .foregroundStyle(.secondary)
                } else if let user = selectedUser {
                    Text(user.decodedName)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text(L10n.string("none"))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !isLoading {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                Form {
                    Section {
                        CheckoutUserPickerContent(
                            searchText: $searchText,
                            users: users,
                            selectedUserId: selectedUser?.id,
                            onSelect: { user in
                                selectedUser = user
                                wasCleared = false
                                showPicker = false
                            }
                        )
                    }
                    if selectedUser != nil {
                        Section {
                            Button(L10n.string("clear_selection"), role: .destructive) {
                                selectedUser = nil
                                wasCleared = true
                                showPicker = false
                            }
                        }
                    }
                }
                .navigationTitle(L10n.string("responsible_party"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("cancel")) { showPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.string("done")) { showPicker = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
}
