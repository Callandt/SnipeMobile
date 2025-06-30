import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @ObservedObject var apiClient: SnipeITAPIClient
    @State private var userId: String = ""
    @Environment(\.dismiss) var dismiss
    @State private var hasLoggedAppearance = false
    @State private var copyNotification: String?
    @State private var showCopyNotification = false
    @State private var selectedTab = 0

    private var assignedUser: User? {
        guard let assignedToId = asset.assignedTo?.id else { return nil }
        return apiClient.users.first { $0.id == assignedToId }
    }

    var body: some View {
        VStack {
            Picker("Details", selection: $selectedTab) {
                Text("Details").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            if selectedTab == 0 {
                detailsView
            } else {
                HistoryView(itemType: "asset", itemId: asset.id, apiClient: apiClient)
            }
        }
        .navigationTitle(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/hardware/\(asset.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            if !hasLoggedAppearance {
                print("AssetDetailView loaded, statusType: \(asset.statusLabel.statusType)")
                hasLoggedAppearance = true
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 100 {
                        dismiss()
                    }
                }
        )
    }

    private var detailsView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if showCopyNotification, let text = copyNotification {
                    Text("Copied: \(text)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(8)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showCopyNotification = false
                                }
                            }
                        }
                }
                
                ScrollView {
                    VStack(spacing: 15) {
                        Text("Device Info")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 5)
                        VStack(spacing: 10) {
                            if !asset.decodedAssetTag.isEmpty {
                                copyableDetailRow(label: "Asset Tag", value: asset.decodedAssetTag)
                            }
                            if !asset.decodedSerial.isEmpty {
                                copyableDetailRow(label: "Serial Number", value: asset.decodedSerial)
                            }
                            if !asset.decodedModelName.isEmpty {
                                copyableDetailRow(label: "Model", value: asset.decodedModelName)
                            }
                            if !asset.decodedManufacturerName.isEmpty {
                                copyableDetailRow(label: "Manufacturer", value: asset.decodedManufacturerName)
                            }
                            if !asset.statusLabel.statusMeta.isEmpty {
                                copyableDetailRow(label: "Status", value: asset.statusLabel.statusMeta)
                            }
                            if !asset.decodedCategoryName.isEmpty {
                                copyableDetailRow(label: "Category", value: asset.decodedCategoryName)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        // Assigned To Section
                        if asset.statusLabel.statusMeta.lowercased() == "deployed", let user = assignedUser {
                            VStack(spacing: 15) {
                                Text("Assigned To")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient)) {
                                    HStack {
                                        Image(systemName: "person.circle")
                                            .foregroundColor(.gray)
                                            .frame(width: 30, height: 30)
                                        VStack(alignment: .leading) {
                                            Text(user.decodedName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(user.decodedEmail)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Text(user.decodedLocationName)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .padding(.top, 5)
                        }

                        Text("Value Info")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 5)
                        VStack(spacing: 10) {
                            if let purchaseCost = asset.purchaseCost, !purchaseCost.isEmpty {
                                copyableDetailRow(label: "Purchase Cost", value: purchaseCost)
                            }
                            if let bookValue = asset.bookValue, !bookValue.isEmpty {
                                copyableDetailRow(label: "Book Value", value: bookValue)
                            }
                            if let orderNumber = asset.orderNumber, !orderNumber.isEmpty {
                                copyableDetailRow(label: "Order Number", value: orderNumber)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        if let customFields = asset.customFields, !customFields.isEmpty {
                            Text("Custom Fields")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                ForEach(customFields.keys.sorted(), id: \.self) { key in
                                    if let value = customFields[key]?.value, !value.isEmpty {
                                        copyableDetailRow(label: key, value: value)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                HStack(spacing: 10) {
                    Button(action: {}) {
                        Text("Edit")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: {}) {
                        Text(asset.statusLabel.statusMeta == "deployed" ? "Check In" : "Check Out")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(asset.statusLabel.statusMeta == "deployed" ? Color.green : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
    }
    
    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).bold()
            Spacer()
            Text(value)
            Button(action: {
                UIPasteboard.general.string = value
                withAnimation {
                    copyNotification = label
                    showCopyNotification = true
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
                    .imageScale(.small)
            }
        }
    }
} 
