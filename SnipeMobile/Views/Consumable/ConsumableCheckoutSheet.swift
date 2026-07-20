import SwiftUI

struct ConsumableCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let consumable: Consumable
    @Binding var isPresented: Bool
    var onSuccess: (() async -> Void)? = nil

    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var userSearchText: String = ""
    @State private var selectedUser: User? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CheckoutUserPickerContent(
                        searchText: $userSearchText,
                        users: filteredUsers,
                        selectedUserId: selectedUser?.id,
                        onSelect: { user in
                            selectedUser = user
                        }
                    )
                } header: {
                    Text(L10n.string("select_user_short"))
                }

                Section {
                    TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(L10n.string("notes"))
                }
            }
            .listStyle(.insetGrouped)
            .formStyle(.grouped)
            .scrollContentBackground(.visible)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("check_out")) { handleCheckout() }
                            .disabled(selectedUser == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .defaultCheckoutUserSelection(apiClient: apiClient, selectedUser: $selectedUser)
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
        }
    }

    var filteredUsers: [User] {
        apiClient.filteredCheckoutUsers(searchText: userSearchText)
    }

    func handleCheckout() {
        guard let user = selectedUser else { return }
        isSaving = true
        Task {
            let success = await apiClient.checkoutConsumable(consumableId: consumable.id, userId: user.id, note: notes)
            if success {
                await onSuccess?()
                await MainActor.run {
                    isPresented = false
                    isSaving = false
                }
            } else {
                await MainActor.run {
                    isSaving = false
                    resultMessage = apiClient.lastApiMessage ?? L10n.string("checkout_failed")
                    showResult = true
                }
            }
        }
    }
}
