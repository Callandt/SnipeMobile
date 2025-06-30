import SwiftUI

struct UserDetailView: View {
    let user: User
    @ObservedObject var apiClient: SnipeITAPIClient
    @State private var copyNotification: String?
    @State private var showCopyNotification = false

    private var assignedAssets: [Asset] {
        apiClient.assets.filter { $0.assignedTo?.id == user.id }
    }

    private var assignedAccessories: [Accessory] {
        apiClient.accessories.filter { $0.assignedTo?.id == user.id }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // --- Fixed Header ---
                VStack(spacing: 15) {
                    Text("User Info")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 15) {
                        if let empNumber = user.employeeNumber, !empNumber.isEmpty {
                            copyableDetailRow(label: "Employee Number", value: empNumber)
                        }
                        
                        if let email = user.email, !email.isEmpty {
                            copyableDetailRow(label: "Email", value: email)
                        }
                        
                        if let locationName = user.location?.name, !locationName.isEmpty {
                            copyableDetailRow(label: "Locatie", value: locationName)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                if !assignedAssets.isEmpty {
                    Text("Assigned Assets")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // --- Scrollable Lists ---
                ScrollView(.vertical) {
                    VStack(spacing: 30) {
                        // Assigned Assets Section
                        if !assignedAssets.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(assignedAssets) { asset in
                                    NavigationLink(destination: AssetDetailView(asset: asset, apiClient: apiClient)) {
                                        AssetCardView(asset: asset)
                                    }
                                }
                            }
                        }

                        // Assigned Accessories Section
                        if !assignedAccessories.isEmpty {
                            VStack(spacing: 10) {
                                Text("Assigned Accessories")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                ForEach(assignedAccessories) { accessory in
                                    AccessoryCardView(accessory: accessory)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .padding(.bottom, 1) // Prevents scrollview from overlapping tab bar
            .padding(.top)

            // Copy notification overlay
            if showCopyNotification, let text = copyNotification {
                VStack {
                    Text("Copied: \(text)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .transition(.opacity.animation(.easeInOut))
                    Spacer()
                }
                .padding(.top)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopyNotification = false
                        }
                    }
                }
            }
        }
        .navigationTitle(user.decodedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/users/\(user.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label + ":")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Spacer()
            
            Button(action: {
                UIPasteboard.general.string = value
                withAnimation {
                    copyNotification = label
                    showCopyNotification = true
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
                    .padding(.leading)
            }
        }
    }
} 