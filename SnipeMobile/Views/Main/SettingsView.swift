import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var apiClient: SnipeITAPIClient

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                TabView {
                    VStack(spacing: 20) {
                        Text("Settings")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }

                    VStack(spacing: 20) {
                        Text("Users")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        if apiClient.isLoading {
                            ProgressView("Loading users...")
                                .progressViewStyle(CircularProgressViewStyle())
                        } else if let error = apiClient.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                        } else {
                            List(apiClient.users) { user in
                                NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient)) {
                                    UserCardView(user: user)
                                }
                            }
                        }
                        Spacer()
                    }
                    .tabItem {
                        Image(systemName: "person.2")
                        Text("Users")
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }
} 