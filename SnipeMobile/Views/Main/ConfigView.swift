import SwiftUI

struct ConfigView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Configure Snipe-IT API")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                TextField("API URL (e.g., https://your-snipeit.com)", text: $baseURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .foregroundColor(.primary)

                SecureField("API Token", text: $apiToken)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .foregroundColor(.primary)

                Button(action: {
                    guard !baseURL.isEmpty, !apiToken.isEmpty else {
                        alertMessage = "Please fill in both the API URL and token."
                        showAlert = true
                        return
                    }
                    apiClient.saveConfiguration(baseURL: baseURL, apiToken: apiToken)
                }) {
                    Text("Save")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                }
            }
            .padding()
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
} 