//
//  SectionPresenceTracker.swift
//  KidBox
//
//  Tiene traccia della sezione aperta, per non notificare ciò che è già a schermo.
//

import SwiftUI

/// Sezioni dell'app che possono "assorbire" una notifica.
///
/// Ogni voce corrisponde alla schermata in cui l'utente vedrebbe comunque il
/// contenuto appena creato, e per cui quindi la notifica sarebbe rumore.
enum KBAppSection: String, Sendable {
    case chat
    case todoList
    case shoppingList
    case calendar
    case notes
    case expenses
    case documents
    case wallet
    case familyLocation
}

/// Registra quale sezione l'utente sta guardando in questo momento.
///
/// Regola generale dell'app: **con l'app in primo piano la notifica si vede
/// comunque**, esattamente come in chat — l'unica eccezione è essere già dentro
/// la sezione in cui il contenuto è appena stato creato, dove lo si vede
/// comparire da solo nella lista e il banner sarebbe solo rumore.
///
/// Gemello di `ScreenPresenceTracker` su Android. È `@unchecked Sendable` con un
/// lock perché a scrivere è la UI sul main actor e a leggere è il delegate delle
/// notifiche, che può essere invocato da un contesto diverso.
final class SectionPresenceTracker: @unchecked Sendable {

    /// - Parameter scopeId: identifica *quale* elemento della sezione si sta
    ///   guardando, quando la sezione ha più contenitori: per i to-do è il
    ///   `listId`, perché essere in una lista non deve zittire le notifiche di
    ///   un'altra. `nil` quando la sezione è unica per famiglia.
    struct Presence: Equatable {
        let section: KBAppSection
        let familyId: String
        let scopeId: String?
    }

    static let shared = SectionPresenceTracker()

    private let lock = NSLock()
    private var current: Presence?

    private init() {}

    /// La sezione descritta da `presence` è aperta e in primo piano.
    func enter(_ presence: Presence) {
        guard !presence.familyId.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        current = presence
    }

    /// L'utente ha lasciato la sezione descritta da `presence`.
    ///
    /// Il confronto evita che una schermata smontata in ritardo cancelli la
    /// presenza di un'altra aperta nel frattempo.
    func leave(_ presence: Presence) {
        lock.lock(); defer { lock.unlock() }
        if current == presence { current = nil }
    }

    /// True se la notifica descritta dai parametri riguarda proprio ciò che
    /// l'utente sta già guardando.
    ///
    /// - Parameter scopeId: lo scope indicato dalla notifica (es. il `listId`
    ///   del to-do). Se la notifica non lo porta si preferisce MOSTRARLA:
    ///   sopprimere senza sapere quale contenitore sia rischierebbe di
    ///   nascondere un avviso relativo a un'altra lista.
    func isViewing(
        section: KBAppSection,
        familyId: String?,
        scopeId: String? = nil,
        scoped: Bool = false
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let presence = current else { return false }
        guard let familyId, !familyId.isEmpty, familyId == presence.familyId else { return false }
        guard presence.section == section else { return false }
        guard scoped else { return true }
        guard let scopeId, !scopeId.isEmpty, let currentScope = presence.scopeId, !currentScope.isEmpty
        else { return false }
        return scopeId == currentScope
    }
}

// MARK: - View modifier

extension View {

    /// Dichiara che questa schermata è la sezione `section` della famiglia
    /// `familyId`, finché resta aperta e in primo piano.
    ///
    /// La presenza è legata a comparsa/scomparsa della schermata: basta, perché
    /// `willPresent` viene chiamato solo con l'app in foreground — con la
    /// schermata aperta ma l'app in background la notifica la mostra il sistema
    /// e questo codice non gira.
    func trackSectionPresence(
        _ section: KBAppSection,
        familyId: String,
        scopeId: String? = nil
    ) -> some View {
        modifier(SectionPresenceModifier(section: section, familyId: familyId, scopeId: scopeId))
    }
}

private struct SectionPresenceModifier: ViewModifier {

    let section: KBAppSection
    let familyId: String
    let scopeId: String?

    private var presence: SectionPresenceTracker.Presence {
        .init(section: section, familyId: familyId, scopeId: scopeId)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { SectionPresenceTracker.shared.enter(presence) }
            .onDisappear { SectionPresenceTracker.shared.leave(presence) }
            // La famiglia attiva può cambiare senza che la schermata scompaia:
            // senza questo, la presenza resterebbe puntata a quella vecchia.
            .onChange(of: familyId) { oldValue, newValue in
                SectionPresenceTracker.shared.leave(
                    .init(section: section, familyId: oldValue, scopeId: scopeId))
                SectionPresenceTracker.shared.enter(
                    .init(section: section, familyId: newValue, scopeId: scopeId))
            }
    }
}
