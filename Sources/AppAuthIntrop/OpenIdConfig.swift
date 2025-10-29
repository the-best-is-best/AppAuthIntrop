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
    public var discoveryUrl:String
    public var clientId:String
    public var redirectUrl:String
    public var scope: String
    public var postLogoutRedirectURL:String


    
    public init(discoveryUrl: String, clientId: String, redirectUrl: String, scope: String, postLogoutRedirectURL: String) {
        self.discoveryUrl = discoveryUrl
        self.clientId = clientId
        self.redirectUrl = redirectUrl
        self.scope = scope
        self.postLogoutRedirectURL = postLogoutRedirectURL
        
    }


}
