//
//  OpenIdConfig.swift
//  AppAuthIntrop
//
//  Created by Michelle Raouf on 27/10/2025.
//

import Foundation

@MainActor
@objcMembers
@objc
public final class KOpenIdConfig: NSObject {

    // Actor داخلي للتخزين الآمن
    private actor Storage {
        var discoveryUrl: String = ""
        var clientId: String = ""
        var redirectUrl: String = ""
        var scope: String = ""
        var postLogoutRedirectURL: String = ""

        // دالة داخل actor لتحديث القيم
        func setConfig(
            discoveryUrl: String,
            clientId: String,
            redirectUrl: String,
            scope: String,
            postLogoutRedirectURL: String
        ) {
            self.discoveryUrl = discoveryUrl
            self.clientId = clientId
            self.redirectUrl = redirectUrl
            self.scope = scope
            self.postLogoutRedirectURL = postLogoutRedirectURL
        }
    }

    private let storage = Storage()

    // Singleton
    @objc public static let shared = KOpenIdConfig()

    private override init() { super.init() }

    // MARK: - Configure
    @objc public func configure(
        discoveryUrl: String,
        clientId: String,
        redirectUrl: String,
        scope: String,
        postLogoutRedirectURL: String
    ) {
        Task { @MainActor in
            await storage.setConfig(
                discoveryUrl: discoveryUrl,
                clientId: clientId,
                redirectUrl: redirectUrl,
                scope: scope,
                postLogoutRedirectURL: postLogoutRedirectURL
            )
        }
    }

    // MARK: - Getters
    @objc public func getDiscoveryUrl() async -> String { await storage.discoveryUrl }
    @objc public func getClientId() async -> String { await storage.clientId }
    @objc public func getRedirectUrl() async -> String { await storage.redirectUrl }
    @objc public func getScope() async -> String { await storage.scope }
    @objc public func getPostLogoutRedirectURL() async -> String { await storage.postLogoutRedirectURL }
}
