//
//  MaxScreenBrightness.swift
//  KidBox
//
//  Porta la luminosità dello schermo al massimo finché una view è visibile,
//  ripristinando il valore precedente quando sparisce. Serve a far leggere un
//  codice a barre dal lettore alla cassa: con la luminosità bassa (o in pieno
//  sole) molti scanner non agganciano il codice. È lo stesso comportamento di
//  Apple Wallet quando mostra una carta.
//
//  ATTENZIONE — su iOS `brightness` cambia la luminosità di SISTEMA, non solo
//  quella dell'app: il ripristino non è una cortesia, è obbligatorio, altrimenti
//  l'utente si ritrova il telefono al massimo (e la batteria che si svuota)
//  dopo aver solo aperto una carta. Per questo il valore precedente viene
//  ripristinato sia all'uscita dalla view sia quando l'app va in background,
//  dove `onDisappear` non viene chiamato.
//

import SwiftUI
import UIKit

private struct MaxScreenBrightnessModifier: ViewModifier {

    /// Consente di sospendere il boost senza smontare la view. Serve perché
    /// presentando uno `sheet` o un `fullScreenCover` la view sottostante NON
    /// riceve `onDisappear` — resta nella gerarchia — quindi senza questo
    /// interruttore la luminosità resterebbe al massimo anche su schermate che
    /// non mostrano nessun codice a barre.
    let isActive: Bool

    /// Luminosità da ripristinare. `nil` = non stiamo forzando nulla, quindi
    /// non c'è niente da ripristinare (evita di "ripristinare" 1.0 su se stesso
    /// se `boost()` venisse chiamato due volte di fila).
    @State private var previousBrightness: CGFloat?

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onDisappear { restore() }
            .onChange(of: isActive) { _, _ in apply() }
            .onChange(of: scenePhase) { _, _ in apply() }
    }

    /// Unico punto che decide: il boost vale solo se richiesto E l'app è in
    /// primo piano. In tutti gli altri casi si ripristina.
    private func apply() {
        if isActive && scenePhase == .active {
            boost()
        } else {
            restore()
        }
    }

    /// `UIScreen.main` è deprecata: lo schermo si prende dalla scena attiva.
    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    private func boost() {
        guard let screen else { return }
        if previousBrightness == nil {
            previousBrightness = screen.brightness
        }
        screen.brightness = 1.0
    }

    private func restore() {
        guard let previousBrightness, let screen else { return }
        screen.brightness = previousBrightness
        self.previousBrightness = nil
    }
}

extension View {
    /// Porta lo schermo alla massima luminosità finché la view è visibile,
    /// ripristinando il valore precedente all'uscita (o quando l'app passa in
    /// background). Vedi il commento in testa al file: la luminosità è di
    /// sistema, quindi il ripristino è parte del contratto.
    ///
    /// - Parameter isActive: passare `false` per sospendere il boost mentre è
    ///   presentato uno `sheet`/`fullScreenCover` che copre il codice: quelle
    ///   presentazioni non generano `onDisappear` sulla view sottostante.
    func maxScreenBrightnessWhileVisible(isActive: Bool = true) -> some View {
        modifier(MaxScreenBrightnessModifier(isActive: isActive))
    }
}
