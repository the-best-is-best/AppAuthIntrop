//
//  KAuthManager.swift
//  AppAuthIntrop
//
//  Created by Michelle Raouf on 27/10/2025.
//

import Foundation
import AppAuth
import kmmcrypto

@objcMembers
public class KAuthManager: NSObject {
    
    @MainActor public static let shared = KAuthManager()
    
    private var authState: OIDAuthState?
    private var currentFlow: OIDExternalUserAgentSession?
    private var configuration: OIDServiceConfiguration?
    
    private var service: String?
    private var group: String?
    
    @objc public func initCrypto(service: String, group: String) {
        self.service = service
        self.group = group
    }
    
    // MARK: - Public getters
    @objc public var accessToken: String? {
        return authState?.lastTokenResponse?.accessToken
    }
    
    @objc public var refreshToken: String? {
        return authState?.lastTokenResponse?.refreshToken
    }
    
    // MARK: - Load OpenID Configuration
    @MainActor private func loadConfiguration(_ completion: @escaping (OIDServiceConfiguration?, Error?) -> Void) {
        if let config = configuration {
            Task { @MainActor in completion(config, nil) }
            return
        }
        
        Task {
            let openId = KOpenIdConfig.shared
            let discoveryUrl = await openId.getDiscoveryUrl()
            
            guard let issuer = URL(string: discoveryUrl) else {
                Task { @MainActor in
                    completion(nil, NSError(domain: "KAuthManager", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Invalid Discovery URL"]))
                }
                return
            }
            
            OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) { config, error in
                Task { @MainActor in
                    self.configuration = config
                    completion(config, error)
                }
            }
        }
    }
    
    // MARK: - Login
    @MainActor
    @objc public func login(_ completion: @escaping (_ success: AuthTokens?, _ error: String?) -> Void) {
        guard let presentingVC = KAuthPresenter.topViewController() else {
            completion(nil, "No active ViewController found")
            return
        }
        
        loadConfiguration { config, error in
            if let error = error {
                completion(nil, "Discovery error: \(error.localizedDescription)")
                return
            }
            guard let config = config else {
                completion(nil, "Configuration missing")
                return
            }
            
            Task {
                let openId = KOpenIdConfig.shared
                guard let redirectURI = URL(string: await openId.getRedirectUrl()) else {
                    await MainActor.run { completion(nil, "Invalid redirect URL") }
                    return
                }
                
                let clientID = await openId.getClientId()
                let scope = await openId.getScope()
                let scopes = scope.split(separator: " ").map { String($0) }
                
                let request = OIDAuthorizationRequest(
                    configuration: config,
                    clientId: clientID,
                    clientSecret: nil,
                    scopes: scopes,
                    redirectURL: redirectURI,
                    responseType: OIDResponseTypeCode,
                    additionalParameters: nil
                )
                
                self.currentFlow = OIDAuthState.authState(
                    byPresenting: request,
                    presenting: presentingVC
                ) { authState, error in
                    Task { @MainActor in
                        if let error = error {
                            completion(nil, "Login failed: \(error.localizedDescription)")
                            return
                        }
                        self.authState = authState
                        self.saveAuthState()
                        let res = authState?.lastTokenResponse
                        completion(
                            AuthTokens(
                                accessToken: res?.accessToken,
                                refreshToken: res?.refreshToken,
                                idToken: res?.idToken
                            ), nil
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Logout
    @MainActor
    @objc public func logout(_ completion: @escaping (Bool, String?) -> Void) {
        guard let presentingVC = KAuthPresenter.topViewController() else {
            completion(false, "No active ViewController found")
            return
        }
        
        guard let authState = authState,
              let idToken = authState.lastTokenResponse?.idToken else {
            completion(false, "No session found")
            return
        }
        
        loadConfiguration { config, error in
            if let error = error {
                completion(false, "Discovery error: \(error.localizedDescription)")
                return
            }
            guard let config = config else {
                completion(false, "Configuration missing")
                return
            }
            
            Task {
                let openId = KOpenIdConfig.shared
                guard let logoutRedirectURI = URL(string: await openId.getPostLogoutRedirectURL()) else {
                    await MainActor.run { completion(false, "Invalid logout redirect URL") }
                    return
                }
                
                let endSessionRequest = OIDEndSessionRequest(
                    configuration: config,
                    idTokenHint: idToken,
                    postLogoutRedirectURL: logoutRedirectURI,
                    state: UUID().uuidString,
                    additionalParameters: nil
                )
                
                guard let userAgent = OIDExternalUserAgentIOS(presenting: presentingVC) else {
                    await MainActor.run { completion(false, "Failed to create user agent") }
                    return
                }
                
                self.currentFlow = OIDAuthorizationService.present(
                    endSessionRequest,
                    externalUserAgent: userAgent
                ) { response, error in
                    Task { @MainActor in
                        if let error = error {
                            completion(false, "Logout failed: \(error.localizedDescription)")
                        } else {
                            self.clearAuthState()
                            completion(true, nil)
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    @objc public func refreshAccessToken(_ completion: @escaping (_ success: AuthTokens?, _ error: String?) -> Void) {
        guard let authState = authState else {
            completion(nil, "No auth state available")
            return
        }

        // Trigger refresh safely
        authState.setNeedsTokenRefresh()
        authState.performAction { [weak self] accessToken, idToken, error in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil, "Instance deallocated")
                }
                return
            }

            if let error = error {
                // Always dispatch to main thread before calling @objc completion
                DispatchQueue.main.async {
                    completion(nil, "Refresh failed: \(error.localizedDescription)")
                }
            } else {
                self.saveAuthState()
                
                let tokens = AuthTokens(
                    accessToken: accessToken,
                    refreshToken: authState.lastTokenResponse?.refreshToken,
                    idToken: idToken
                )
                
                DispatchQueue.main.async {
                    completion(tokens, nil)
                }
            }
        }
    }

    
    @MainActor
    @objc public func getAuthTokens() -> AuthTokens? {
        loadAuthState()
        guard let authState = self.authState else { return nil }
        return AuthTokens(
            accessToken: authState.lastTokenResponse?.accessToken,
            refreshToken: authState.lastTokenResponse?.refreshToken,
            idToken: authState.lastTokenResponse?.idToken
        )
    }
    
    // MARK: - User Info
    @objc public func getUserInfo(_ completion: @escaping ([String: Any]?, String?) -> Void) {
        loadAuthState()
        guard let accessToken = authState?.lastTokenResponse?.accessToken else {
            completion(nil, "No access token available")
            return
        }
        
        guard let endpoint = authState?.lastAuthorizationResponse.request.configuration.discoveryDocument?.userinfoEndpoint else {
            completion(nil, "UserInfo endpoint not found")
            return
        }
        
        var request = URLRequest(url: endpoint)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion(nil, "Invalid response")
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(json, nil)
                } else {
                    completion(nil, "Invalid JSON")
                }
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
        task.resume()
    }
    
    // MARK: - Persistence (Keychain + fallback)
    private func saveAuthState() {
        guard let state = authState else { return }
        guard let service = self.service, let group = self.group else {
            print("🔐 Service/group not initialized — abort save")
            return
        }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            IOSCryptoManager.saveDataType(service: service, account: group, data: data) { error in
                if let error = error {
                    print("🔐 Save auth state failed: \(error.localizedDescription)")
                } else {
                    print("🔐 Auth state saved securely in Keychain")
                }
            }
        } catch {
            print("🔐 Secure archiving failed: \(error). Trying fallback.")
            do {
                let fallback = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false)
                IOSCryptoManager.saveDataType(service: service, account: group, data: fallback) { err in
                    if let err = err {
                        print("🔐 Fallback save failed: \(err.localizedDescription)")
                    } else {
                        print("🔐 Fallback auth state saved (non-secure).")
                    }
                }
            } catch {
                print("🔐 Fallback archiving also failed: \(error)")
            }
        }
    }
    
    private func loadAuthState() {
        guard let service = self.service, let group = self.group else {
            print("🔐 Service/group not initialized — abort load")
            return
        }
        IOSCryptoManager.getDataType(service: service, account: group) { data, error in
            if let error = error {
                print("🔐 Load auth state failed: \(error.localizedDescription)")
                return
            }
            guard let data = data as Data? else { return }
            do {
                if let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
                    self.authState = state
                    print("🔐 Auth state loaded successfully from Keychain")
                }
            } catch {
                print("🔐 Load auth state decoding failed: \(error)")
            }
        }
    }
    
    private func clearAuthState() {
        authState = nil
        guard let service = self.service, let group = self.group else { return }
        IOSCryptoManager.deleteData(service: service, account: group)
        print("🔐 Auth state cleared from Keychain")
    }
}
