//
//  KAuthManager.swift
//  AppAuthIntrop
//
//  Created by Michelle Raouf on 27/10/2025.
//

import AppAuth
import Foundation
import kmmcrypto

@objcMembers
@MainActor
public class KAuthManager: NSObject {

    public static let shared = KAuthManager()

    // MARK: - Private Properties
    private var authState: OIDAuthState?
    private var currentFlow: OIDExternalUserAgentSession?
    private var configuration: OIDServiceConfiguration?
    private var service: String?
    private var group: String?
    private var openId: KOpenIdConfig?
    
    // MARK: - Public Properties
    @objc public var accessToken: String? {
        return authState?.lastTokenResponse?.accessToken
    }

    @objc public var refreshToken: String? {
        return authState?.lastTokenResponse?.refreshToken
    }

    // MARK: - Initialization
    @objc public func initCrypto(service: String, group: String, client: KOpenIdConfig) {
        self.service = service
        self.group = group
        self.openId = client
    }

    // MARK: - Configuration
    private func loadConfiguration() async throws -> OIDServiceConfiguration {
        if let config = configuration {
            return config
        }

        guard let discoveryUrl = openId?.discoveryUrl,
              let issuer = URL(string: discoveryUrl) else {
            throw NSError(
                domain: "KAuthManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Discovery URL"]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) { config, error in
                Task { @MainActor in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let config = config {
                        self.configuration = config
                        continuation.resume(returning: config)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "KAuthManager",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Configuration missing"]
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Login
    @objc public func login(_ completion: @escaping (_ success: AuthTokens?, _ error: String?) -> Void) {
        Task {
            do {
                guard let presentingVC =  KAuthPresenter.topViewController() else {
                    await MainActor.run { completion(nil, "No active ViewController found") }
                    return
                }

                let config = try await loadConfiguration()
                
                guard let redirectURI = URL(string: self.openId!.redirectUrl) else {
                    await MainActor.run { completion(nil, "Invalid redirect URL") }
                    return
                }

                let clientID = self.openId!.clientId
                let scope = self.openId!.scope
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

                let authState = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OIDAuthState, Error>) in
                    // Use a local variable to avoid capturing self
                    let localRequest = request
                    let localPresentingVC = presentingVC
                    
                    self.currentFlow = OIDAuthState.authState(
                        byPresenting: localRequest,
                        presenting: localPresentingVC
                    ) { authState, error in
                        // Ensure we're on MainActor when handling the result
                        Task { @MainActor in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else if let authState = authState {
                                continuation.resume(returning: authState)
                            } else {
                                continuation.resume(throwing: NSError(
                                    domain: "KAuthManager",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Auth state missing"]
                                ))
                            }
                        }
                    }
                }

                // We're already on MainActor here due to the class being @MainActor
                self.authState = authState
                await self.saveAuthState()
                
                let res = authState.lastTokenResponse
                let tokens = AuthTokens(
                    accessToken: res?.accessToken ?? "",
                    refreshToken: res?.refreshToken ?? "",
                    idToken: res?.idToken ?? ""
                )
                
                completion(tokens, nil)

            } catch {
                completion(nil, "Login failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Logout
    @objc public func logout(_ completion: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                guard let presentingVC =  KAuthPresenter.topViewController() else {
                    await MainActor.run { completion(false, "No active ViewController found") }
                    return
                }

                guard let authState = self.authState,
                      let idToken = authState.lastTokenResponse?.idToken else {
                    await MainActor.run { completion(false, "No session found") }
                    return
                }

                let config = try await loadConfiguration()
                
                guard let logoutRedirectURI = URL(string: self.openId!.postLogoutRedirectURL) else {
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

                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.currentFlow = OIDAuthorizationService.present(
                        endSessionRequest,
                        externalUserAgent: userAgent
                    ) { response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }

                self.clearAuthState()
                await MainActor.run { completion(true, nil) }

            } catch {
                await MainActor.run {
                    completion(false, "Logout failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Token Management
    @objc public func refreshAccessToken(_ completion: @escaping (_ success: AuthTokens?, _ error: String?) -> Void) {
        Task {
            do {
                await loadAuthState()
                
                guard let authState = self.authState else {
                    await MainActor.run { completion(nil, "No auth state available") }
                    return
                }

                authState.setNeedsTokenRefresh()
                
                let (accessToken, idToken) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String?, String?), Error>) in
                    authState.performAction { accessToken, idToken, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: (accessToken, idToken))
                        }
                    }
                }

                await self.saveAuthState()

                let tokens = AuthTokens(
                    accessToken: accessToken ?? "",
                    refreshToken: authState.lastTokenResponse?.refreshToken ?? "",
                    idToken: idToken ?? ""
                )

                await MainActor.run { completion(tokens, nil) }

            } catch {
                await MainActor.run {
                    completion(nil, "Refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc(getAuthTokens:)
    public func getAuthTokens(completion: @escaping (AuthTokens?) -> Void) {
        Task {
            await loadAuthState()

            guard let authState = self.authState else {
                await MainActor.run { completion(nil) }
                return
            }

            do {
                let (accessToken, idToken) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String?, String?), Error>) in
                    authState.performAction { accessToken, idToken, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: (accessToken, idToken))
                        }
                    }
                }

                let tokens = AuthTokens(
                    accessToken: accessToken ?? "",
                    refreshToken: authState.lastTokenResponse?.refreshToken ?? "",
                    idToken: idToken ?? authState.lastTokenResponse?.idToken ?? ""
                )

                await MainActor.run { completion(tokens) }

            } catch {
                print("Error getting auth tokens: \(error)")
                await MainActor.run { completion(nil) }
            }
        }
    }

    // MARK: - User Info
    @objc public func getUserInfo(_ completion: @escaping ([String: Any]?, String?) -> Void) {
        Task {
            await loadAuthState()

            guard let accessToken = authState?.lastTokenResponse?.accessToken else {
                await MainActor.run { completion(nil, "No access token available") }
                return
            }

            guard let endpoint = authState?.lastAuthorizationResponse.request.configuration
                    .discoveryDocument?.userinfoEndpoint else {
                await MainActor.run { completion(nil, "UserInfo endpoint not found") }
                return
            }

            var request = URLRequest(url: endpoint)
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    await MainActor.run { completion(nil, "Invalid response") }
                    return
                }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run { completion(json, nil) }
                } else {
                    await MainActor.run { completion(nil, "Invalid JSON") }
                }
            } catch {
                await MainActor.run { completion(nil, error.localizedDescription) }
            }
        }
    }

    // MARK: - Persistence
    private func saveAuthState() async {
        guard let state = authState,
              let service = self.service,
              let group = self.group else {
            print("🔐 Service/group not initialized — abort save")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: state, requiringSecureCoding: true)
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                IOSCryptoManager.saveDataType(service: service, account: group, data: data) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        print("🔐 Auth state saved securely in Keychain")
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            print("🔐 Secure archiving failed: \(error). Trying fallback.")
            do {
                let fallback = try NSKeyedArchiver.archivedData(
                    withRootObject: state, requiringSecureCoding: false)
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    IOSCryptoManager.saveDataType(service: service, account: group, data: fallback) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            print("🔐 Fallback auth state saved (non-secure).")
                            continuation.resume(returning: ())
                        }
                    }
                }
            } catch {
                print("🔐 Fallback archiving also failed: \(error)")
            }
        }
    }

    private func loadAuthState() async {
        guard let service = self.service, let group = self.group else {
            print("🔐 Service/group not initialized — abort load")
            return
        }

        do {
            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                IOSCryptoManager.getDataType(service: service, account: group) { nsData, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let nsData = nsData {
                        continuation.resume(returning: nsData as Data)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "KAuthManager",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No data found in Keychain"]
                        ))
                    }
                }
            }

            if let authState = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: OIDAuthState.self, from: data) {
                self.authState = authState
                print("🔐 Auth state loaded successfully from Keychain")
            } else {
                print("🔐 Decoding returned nil")
                self.authState = nil
            }
        } catch {
            print("🔐 Load auth state failed: \(error)")
            self.authState = nil
        }
    }

    private func clearAuthState() {
        authState = nil
        guard let service = self.service, let group = self.group else { return }
        
        IOSCryptoManager.deleteData(service: service, account: group)
    }
}
