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

    /// Orientamenti di default: tutti su iPad e sullo schermo grande dell'iPhone
    /// Duo aperto (larghezza E altezza regular), portrait sull'iPhone e sul Duo
    /// chiuso. Non basta la larghezza: un iPhone Max in orizzontale ha larghezza
    /// regular, e dopo l'anteprima di un PDF non tornerebbe più in verticale.
    static func defaultMask(for scene: UIWindowScene?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        guard let traits = scene?.traitCollection else { return .portrait }
        let large = traits.horizontalSizeClass == .regular && traits.verticalSizeClass == .regular
        return large ? .all : .portrait
    }

    /// Consente la rotazione (portrait + landscape, escluso capovolto) e forza
    /// l'aggiornamento della geometria.
    static func unlock() { apply(.allButUpsideDown) }

    /// Ripristina gli orientamenti di default (riporta a portrait su iPhone).
    static func reset() { apply(nil) }

    /// Rilegge la maschera di default dopo un cambio di schermo (il Duo che si
    /// apre o si chiude), se nessuna anteprima la sta forzando.
    static func refresh() {
        guard AppDelegate.supportedOrientations == nil else { return }
        apply(nil)
    }

    private static func apply(_ override: UIInterfaceOrientationMask?) {
        AppDelegate.supportedOrientations = override
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let mask = override ?? defaultMask(for: scene)

        if #available(iOS 16.0, *) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        } else {
            // Pre-iOS 16: forza la rotazione tramite l'orientamento del dispositivo.
            let value = (override != nil)
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
