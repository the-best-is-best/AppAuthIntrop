import SwiftUI
import AppAuthIntrop

struct ContentView: View {
    
    @State private var statusText: String = "Ready to test OAuth"
    @State private var userInfoText: String = ""
    @State private var tokenInfoText: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            
            Image(systemName: "lock.shield")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("OAuth Test App")
                .font(.title2)
                .bold()
            
            Text(statusText)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
            
            HStack(spacing: 12) {
                
                Button("Login") {
                    statusText = "Starting login..."
                    KAuthManager.shared.login { success, error in
                        Task { @MainActor in
                            if success {
                                statusText = "✅ Login Success"
                                loadTokens()
                            } else {
                                statusText = "❌ Login Failed: \(error ?? "Unknown")"
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Refresh Token") {
                    statusText = "Refreshing access token..."
                    KAuthManager.shared.refreshAccessToken { success, error in
                        Task { @MainActor in
                            if success {
                                statusText = "✅ Token refreshed"
                                loadTokens()
                            } else {
                                statusText = "❌ Refresh failed: \(error ?? "Unknown")"
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Button("Get User Info") {
                statusText = "Fetching user info..."
                
                KAuthManager.shared.getUserInfo { info, error in
                    Task { @MainActor in
                        if let info = info {
                            userInfoText = info.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                            statusText = "✅ User Info fetched"
                        } else {
                            userInfoText = ""
                            statusText = "❌ Failed: \(error ?? "Unknown")"
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            
            Button("Logout") {
                statusText = "Logging out..."
                
                KAuthManager.shared.logout { success, error in
                    Task { @MainActor in
                        if success {
                            statusText = "✅ Logout Success"
                            userInfoText = ""
                            tokenInfoText = ""
                        } else {
                            statusText = "❌ Logout Failed: \(error ?? "Unknown")"
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            
            // MARK: - Tokens
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !tokenInfoText.isEmpty {
                        Text("🔑 Tokens:")
                            .font(.headline)
                        Text(tokenInfoText)
                            .font(.caption)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .textSelection(.enabled) // يمكن نسخ التوكن
                    }
                    
                    if !userInfoText.isEmpty {
                        Text("👤 User Info:")
                            .font(.headline)
                        Text(userInfoText)
                            .font(.caption)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            
            Spacer()
        }
        .padding()
    }
    
    private func loadTokens() {
        Task { @MainActor in
            let accessToken = KAuthManager.shared.accessToken ?? "N/A"
            let refreshToken = KAuthManager.shared.refreshToken ?? "N/A"
            tokenInfoText = "Access Token:\n\(accessToken)\n\nRefresh Token:\n\(refreshToken)"
        }
    }
}

#Preview {
    ContentView()
}
