import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @ObservedObject var apiClient: SnipeITAPIClient
    @State private var userId: String = ""
    @Environment(\.dismiss) var dismiss
    @State private var hasLoggedAppearance = false
    @State private var copyNotification: String?
    @State private var showCopyNotification = false

    private var assignedUser: User? {
        guard let assignedToId = asset.assignedTo?.id else { return nil }
        return apiClient.users.first { $0.id == assignedToId }
    }

    var body: some View {
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
                
                Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding(.top)
                
                ScrollView {
                    VStack(spacing: 15) {
                        Text("Device Info")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 5)
                        VStack(spacing: 10) {
                            if !asset.decodedAssetTag.isEmpty {
                                HStack {
                                    Text("Asset Tag").bold()
                                    Spacer()
                                    Text(asset.decodedAssetTag)
                                    Button(action: {
                                        UIPasteboard.general.string = asset.decodedAssetTag
                                        withAnimation {
                                            copyNotification = "Asset Tag"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if !asset.decodedSerial.isEmpty {
                                HStack {
                                    Text("Serial Number").bold()
                                    Spacer()
                                    Text(asset.decodedSerial)
                                    Button(action: {
                                        UIPasteboard.general.string = asset.decodedSerial
                                        withAnimation {
                                            copyNotification = "Serial Number"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if !asset.decodedModelName.isEmpty {
                                HStack {
                                    Text("Model").bold()
                                    Spacer()
                                    Text(asset.decodedModelName)
                                    Button(action: {
                                        UIPasteboard.general.string = asset.decodedModelName
                                        withAnimation {
                                            copyNotification = "Model"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if !asset.decodedManufacturerName.isEmpty {
                                HStack {
                                    Text("Manufacturer").bold()
                                    Spacer()
                                    Text(asset.decodedManufacturerName)
                                    Button(action: {
                                        UIPasteboard.general.string = asset.decodedManufacturerName
                                        withAnimation {
                                            copyNotification = "Manufacturer"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if !asset.statusLabel.statusMeta.isEmpty {
                                HStack {
                                    Text("Status").bold()
                                    Spacer()
                                    Text(asset.statusLabel.statusMeta)
                                    Button(action: {
                                        UIPasteboard.general.string = asset.statusLabel.statusMeta
                                        withAnimation {
                                            copyNotification = "Status"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if !asset.decodedCategoryName.isEmpty {
                                HStack {
                                    Text("Category").bold()
                                    Spacer()
                                    Text(asset.decodedCategoryName)
                                    Button(action: {
                                        UIPasteboard.general.string = asset.decodedCategoryName
                                        withAnimation {
                                            copyNotification = "Category"
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
                                HStack {
                                    Text("Purchase Cost").bold()
                                    Spacer()
                                    Text(purchaseCost)
                                    Button(action: {
                                        UIPasteboard.general.string = purchaseCost
                                        withAnimation {
                                            copyNotification = "Purchase Cost"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let bookValue = asset.bookValue, !bookValue.isEmpty {
                                HStack {
                                    Text("Book Value").bold()
                                    Spacer()
                                    Text(bookValue)
                                    Button(action: {
                                        UIPasteboard.general.string = bookValue
                                        withAnimation {
                                            copyNotification = "Book Value"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let orderNumber = asset.orderNumber, !orderNumber.isEmpty {
                                HStack {
                                    Text("Order Number").bold()
                                    Spacer()
                                    Text(orderNumber)
                                    Button(action: {
                                        UIPasteboard.general.string = orderNumber
                                        withAnimation {
                                            copyNotification = "Order Number"
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
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        Text("Dates")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 5)
                        VStack(spacing: 10) {
                            if let purchaseDate = asset.purchaseDate?.formatted, !purchaseDate.isEmpty {
                                HStack {
                                    Text("Purchase Date").bold()
                                    Spacer()
                                    Text(purchaseDate)
                                    Button(action: {
                                        UIPasteboard.general.string = purchaseDate
                                        withAnimation {
                                            copyNotification = "Purchase Date"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let warrantyExpires = asset.warrantyExpires?.formatted, !warrantyExpires.isEmpty {
                                HStack {
                                    Text("Warranty Expires").bold()
                                    Spacer()
                                    Text(warrantyExpires)
                                    Button(action: {
                                        UIPasteboard.general.string = warrantyExpires
                                        withAnimation {
                                            copyNotification = "Warranty Expires"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let eolDate = asset.assetEolDate?.formatted, !eolDate.isEmpty {
                                HStack {
                                    Text("EOL Date").bold()
                                    Spacer()
                                    Text(eolDate)
                                    Button(action: {
                                        UIPasteboard.general.string = eolDate
                                        withAnimation {
                                            copyNotification = "EOL Date"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let nextAuditDate = asset.nextAuditDate?.formatted, !nextAuditDate.isEmpty {
                                HStack {
                                    Text("Next Audit").bold()
                                    Spacer()
                                    Text(nextAuditDate)
                                    Button(action: {
                                        UIPasteboard.general.string = nextAuditDate
                                        withAnimation {
                                            copyNotification = "Next Audit"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let lastAuditDate = asset.lastAuditDate?.formatted, !lastAuditDate.isEmpty {
                                HStack {
                                    Text("Last Audit").bold()
                                    Spacer()
                                    Text(lastAuditDate)
                                    Button(action: {
                                        UIPasteboard.general.string = lastAuditDate
                                        withAnimation {
                                            copyNotification = "Last Audit"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let lastCheckout = asset.lastCheckout?.formatted, !lastCheckout.isEmpty {
                                HStack {
                                    Text("Last Checkout").bold()
                                    Spacer()
                                    Text(lastCheckout)
                                    Button(action: {
                                        UIPasteboard.general.string = lastCheckout
                                        withAnimation {
                                            copyNotification = "Last Checkout"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let lastCheckin = asset.lastCheckin?.formatted, !lastCheckin.isEmpty {
                                HStack {
                                    Text("Last Checkin").bold()
                                    Spacer()
                                    Text(lastCheckin)
                                    Button(action: {
                                        UIPasteboard.general.string = lastCheckin
                                        withAnimation {
                                            copyNotification = "Last Checkin"
                                            showCopyNotification = true
                                        }
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            if let expectedCheckin = asset.expectedCheckin?.formatted, !expectedCheckin.isEmpty {
                                HStack {
                                    Text("Expected Checkin").bold()
                                    Spacer()
                                    Text(expectedCheckin)
                                    Button(action: {
                                        UIPasteboard.general.string = expectedCheckin
                                        withAnimation {
                                            copyNotification = "Expected Checkin"
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
                                        HStack {
                                            Text(key).bold()
                                            Spacer()
                                            Text(value)
                                            Button(action: {
                                                UIPasteboard.general.string = value
                                                withAnimation {
                                                    copyNotification = key
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
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
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
                .padding(.bottom, 10)
            }
            .padding()
        }
        .navigationBarTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                        Text("Back")
                            .foregroundColor(.blue)
                            .font(.system(size: 17))
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
} 