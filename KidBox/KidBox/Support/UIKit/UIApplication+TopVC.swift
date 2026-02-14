//
//  UIApplication+TopVC.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import UIKit
internal import os

/// Utility per ottenere il view controller “in cima” allo stack di presentazione.
///
/// - Important:
///   - Nessun `print`.
///   - Log minimale: solo quando non troviamo root/scene, per debug di integrazione.
///   - Nessuna modifica di logica (stesso algoritmo di risalita).
extension UIApplication {
    
    /// Ritorna il view controller attualmente visibile (presented/nav/tab), partendo dal root della key window.
    ///
    /// - Returns: `UIViewController` più in alto, oppure `nil` se non esiste una window/scene valida.
    var topMostViewController: UIViewController? {
        guard
            let windowScene = connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = windowScene.keyWindow?.rootViewController
        else {
            KBLog.navigation.debug("topMostViewController: no active windowScene/rootViewController")
            return nil
        }
        
        return root.topMostViewController()
    }
}

private extension UIViewController {
    
    /// Risale ricorsivamente lo stack:
    /// 1) presentedViewController
    /// 2) UINavigationController.visibleViewController
    /// 3) UITabBarController.selectedViewController
    /// altrimenti ritorna `self`.
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
