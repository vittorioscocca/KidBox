//
//  UIApplication+TopVC.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import UIKit

extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let windowScene = connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = windowScene.keyWindow?.rootViewController else {
            return nil
        }
        return root.topMostViewController()
    }
}

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.topMostViewController()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.topMostViewController()
        }
        return self
    }
}
