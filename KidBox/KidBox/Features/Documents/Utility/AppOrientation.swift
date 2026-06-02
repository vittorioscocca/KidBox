//
//  AppOrientation.swift
//  KidBox
//
//  Sblocco temporaneo della rotazione per l'anteprima documenti/PDF.
//

import SwiftUI
import UIKit

/// Gestisce la maschera orientamenti dell'app (vedi `AppDelegate.supportedOrientations`).
/// Usato per consentire la rotazione solo mentre è aperta un'anteprima a tutto schermo,
/// mantenendo il resto dell'app in portrait su iPhone.
enum AppOrientation {

    /// Orientamenti di default in base al dispositivo (iPhone portrait, iPad tutti).
    static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    /// Consente la rotazione (portrait + landscape, escluso capovolto) e forza
    /// l'aggiornamento della geometria.
    static func unlock() { apply(.allButUpsideDown) }

    /// Ripristina gli orientamenti di default (riporta a portrait su iPhone).
    static func reset() { apply(defaultMask) }

    private static func apply(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.supportedOrientations = mask
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        if #available(iOS 16.0, *) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        } else {
            // Pre-iOS 16: forza la rotazione tramite l'orientamento del dispositivo.
            let value = (mask != defaultMask)
                ? UIInterfaceOrientation.unknown.rawValue
                : UIInterfaceOrientation.portrait.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

private struct AllowAllOrientationsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { AppOrientation.unlock() }
            .onDisappear { AppOrientation.reset() }
    }
}

extension View {
    /// Consente la rotazione mentre la view è visibile; ripristina il default alla scomparsa.
    /// Pensato per anteprime documenti/PDF a tutto schermo.
    func allowsAllOrientationsWhileVisible() -> some View {
        modifier(AllowAllOrientationsModifier())
    }
}
