//
//  ContentView.swift
//  TestAppAuthIntrop
//
//  Created by Michelle Raouf on 27/10/2025.
//

import SwiftUI
import AppAuthIntrop

struct ContentView: View {
    
    @State private var statusText: String = "Ready to test OAuth"
    @State private var userInfoText: String = ""
    

    
    
    
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
            
            // MARK: - Buttons
            
            Button("Login") {
                statusText = "Starting login..."
                
                KAuthManager.shared.login { success, error in
                    Task { @MainActor in
                        if success {
                            statusText = "✅ Login Success"
                        } else {
                            statusText = "❌ Login Failed: \(error ?? "Unknown")"
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
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
                        } else {
                            statusText = "❌ Logout Failed: \(error ?? "Unknown")"
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            
            ScrollView {
                if !userInfoText.isEmpty {
                    Text(userInfoText)
                        .font(.caption)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 200)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
