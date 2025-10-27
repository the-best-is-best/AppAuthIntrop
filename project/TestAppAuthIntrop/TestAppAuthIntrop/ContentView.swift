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
                    KAuthManager.shared.login { authRes, error in
                        Task { @MainActor in
                            if let error = error {
                                statusText = "❌ Login Failed: \(error)"
                            } else if let authRes = authRes {
                                statusText = "✅ Login Success"
                                updateTokenInfo(authRes)
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Refresh Token") {
                    statusText = "Refreshing access token..."
                    KAuthManager.shared.refreshAccessToken { authRes, error in
                        Task { @MainActor in
                            if let error = error {
                                statusText = "❌ Refresh failed: \(error)"
                            } else if let authRes = authRes {
                                statusText = "✅ Token refreshed"
                                updateTokenInfo(authRes)
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            
            HStack(spacing: 12) {
                
                Button("Get Auth Tokens") {
                    statusText = "Getting auth tokens..."
                    Task { @MainActor in
                        if let authTokens = KAuthManager.shared.getAuthTokens() {
                            updateTokenInfo(authTokens)
                            statusText = "✅ Auth Tokens fetched"
                        } else {
                            tokenInfoText = ""
                            statusText = "❌ No auth tokens available"
                        }
                    }
                }
                .buttonStyle(.bordered)
                
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
            }
            
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
                                .textSelection(.enabled)
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
    
    // ✅ الدالة يجب أن تكون خارج body
    private func updateTokenInfo(_ tokens: AuthTokens) {
        tokenInfoText = """
        Access Token:
        \(tokens.accessToken ?? "N/A")
        
        Refresh Token:
        \(tokens.refreshToken ?? "N/A")
        
        ID Token:
        \(tokens.idToken ?? "N/A")
        """
    }
}

// ✅ Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
