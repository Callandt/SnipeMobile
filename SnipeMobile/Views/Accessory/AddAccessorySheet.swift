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
                Section(header: Text("General")) {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Choose category…").tag(0)
                        ForEach(apiClient.categories) { cat in
                            Text(HTMLDecoder.decode(cat.name)).tag(cat.id)
                        }
                    }
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                }
            }
            .navigationTitle("New accessory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { saveAccessory() }
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
            .alert("Result", isPresented: $showResult) {
                Button("OK") {
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
