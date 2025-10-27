//
//  TestAppAuthIntropApp.swift
//  TestAppAuthIntrop
//
//  Created by Michelle Raouf on 27/10/2025.
//

import SwiftUI
import AppAuthIntrop

@main
struct TestAppAuthIntropApp: App {
    init (){
        
        OpenIdConfig.shared.configure(
            discoveryUrl: "https://demo.duendesoftware.com", // فقط issuer
            clientId: "interactive.public",
            redirectUrl: "com.duendesoftware.demo:/oauthredirect",
            scope: "openid profile email api",
            postLogoutRedirectURL: "com.duendesoftware.demo:/"
        )
        KAuthManager.shared.initCrypto(service: "auth", group: "kmmOpenId")
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
