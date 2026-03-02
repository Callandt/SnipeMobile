import SwiftUI

struct AddAccessorySheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedCategoryId: Int = 0
    @State private var quantity: Int = 1
    @State private var isSaving = false
    @State private var resultMessage = ""
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L10n.string("general"))) {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $selectedCategoryId) {
                        Text(L10n.string("choose_category")).tag(0)
                        ForEach(apiClient.categories) { cat in
                            Text(HTMLDecoder.decode(cat.name)).tag(cat.id)
                        }
                    }
                    Stepper("\(L10n.string("quantity")): \(quantity)", value: $quantity, in: 1...9999)
                }
            }
            .navigationTitle(L10n.string("new_accessory"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("create")) { saveAccessory() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategoryId == 0)
                    }
                }
            }
            .onAppear {
                if apiClient.categories.isEmpty {
                    Task { await apiClient.fetchCategories() }
                }
                if selectedCategoryId == 0, let first = apiClient.categories.first {
                    selectedCategoryId = first.id
                }
            }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok")) {
                    if resultMessage.contains("created") {
                        isPresented = false
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    private func saveAccessory() {
        guard selectedCategoryId != 0 else { return }
        isSaving = true
        Task {
            let success = await apiClient.createAccessory(
                name: name.trimmingCharacters(in: .whitespaces),
                categoryId: selectedCategoryId,
                quantity: quantity,
                customFields: nil
            )
            isSaving = false
            resultMessage = apiClient.lastApiMessage ?? (success ? "Accessory created!" : "Create failed.")
            showResult = true
        }
    }
}
