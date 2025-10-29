//
//  AuthTokens.swift
//  AppAuthIntrop
//
//  Created by Michelle Raouf on 27/10/2025.
//

import Foundation

@objcMembers
@objc
public class AuthTokens: NSObject {
    public var accessToken: String?
    public var refreshToken: String?
    public var idToken: String?
    
    public init(accessToken: String?, refreshToken: String?, idToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
    }
}




