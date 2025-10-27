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
    
//    private override init() {
//        super.init()
//        loadAuthState()
//    }
    
  @objc public  func initCrypto(service: String , group:String){
      self.service = service
      self.group = group
        
    }
    
    // MARK: - Load OpenID Configuration
   @MainActor private func loadConfiguration(_ completion: @escaping (OIDServiceConfiguration?, Error?) -> Void) {
        // Capture completion locally
        let completion = completion

        if let config = configuration {
            Task { @MainActor in
                completion(config, nil)
            }
            return
        }
        
        Task {
            let openId =  KOpenIdConfig.shared
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
    @objc public func login(_ completion: @escaping (Bool, String?) -> Void) {
        guard let presentingVC = KAuthPresenter.topViewController() else {
            completion(false, "No active ViewController found")
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
                let openId =  KOpenIdConfig.shared
                
                guard let redirectURI = URL(string: await openId.getRedirectUrl()) else {
                    await MainActor.run { completion(false, "Invalid redirect URL") }
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
                            completion(false, "Login failed: \(error.localizedDescription)")
                            return
                        }
                        self.authState = authState
                        self.saveAuthState()
                        completion(true, nil)
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
                let openId =  KOpenIdConfig.shared
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
    @objc
    public func refreshAccessToken(_ completion: @escaping (Bool, String?) -> Void) {
        guard let authState = authState else {
            completion(false, "No auth state available")
            return
        }

        authState.setNeedsTokenRefresh()
        authState.performAction { accessToken, idToken, error in
            if let error = error {
                completion(false, "Refresh failed: \(error.localizedDescription)")
            } else {
                // توكن جديد تم تحديثه تلقائيًا
                self.saveAuthState() // احفظ الحالة الجديدة
                completion(true, nil)
            }
        }
    }

    
    // MARK: - Get User Info
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
    
    // MARK: - Persistence using Keychain (kmmcrypto)
    private func saveAuthState() {
        guard let state = authState else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            IOSCryptoManager.saveDataType(service: self.service!, account: self.group!, data: data) { error in
                if let error = error {
                    print("🔐 Save auth state failed: \(error.localizedDescription)")
                } else {
                    print("🔐 Auth state saved securely in Keychain")
                }
            }
        } catch {
            print("🔐 Save auth state serialization failed: \(error)")
        }
    }
    
    private func loadAuthState() {
        IOSCryptoManager.getDataType(service: self.service!, account: self.group!) { data, error in
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
        IOSCryptoManager.deleteData(service: self.service!, account: self.group!)
        print("🔐 Auth state cleared from Keychain")
    }
}
