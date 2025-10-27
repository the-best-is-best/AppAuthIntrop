//
//  KAuthPresenter.swift
//
//
//  Created by Michelle Raouf on 27/10/2025.
//

#if canImport(UIKit)
import UIKit

@objcMembers
public class KAuthPresenter: NSObject {
    
    /// Returns the top-most view controller to present login/logout UI
    @MainActor
    @objc public static func topViewController() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            return nil
        }
        return findTopViewController(from: root)
    }
    
    /// Recursively finds the top-most visible controller
    @MainActor
    private static func findTopViewController(from controller: UIViewController?) -> UIViewController? {
        if let nav = controller as? UINavigationController {
            return findTopViewController(from: nav.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return findTopViewController(from: tab.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return findTopViewController(from: presented)
        }
        return controller
    }
}

#endif
