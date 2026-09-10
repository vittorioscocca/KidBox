//
//  AlexaPromoBanner.swift
//  KidBox
//
//  L'invito a collegare Alexa, dentro le due schermate dove la skill serve
//  davvero: la lista della spesa e i to-do.
//
//  Perché qui e non solo in Impostazioni: la skill esiste da settembre e
//  nessuno la trova, perché per scoprirla bisogna già sapere che c'è e andarla
//  a cercare in fondo alle impostazioni. Chi sta guardando la lista della spesa
//  è invece esattamente la persona a cui interessa dettarla a voce.
//
//  Tre condizioni perché compaia, e servono tutte:
//    1. la skill esiste nella lingua dell'app (`AlexaAvailability`): proporre a
//       un francese di collegare una skill che risponde solo in italiano è
//       peggio che tacere;
//    2. la famiglia non è già collegata — e vale il collegamento di CHIUNQUE,
//       non solo il proprio: se in casa un membro ha già agganciato l'account
//       Amazon, gli Echo funzionano per tutti e l'invito è rumore;
//    3. l'utente non ha già detto di no.
//

import SwiftUI
import FirebaseFunctions
import Combine

/// Memoria dell'invito, sul dispositivo ma per famiglia.
///
/// Non sincronizzata: è una preferenza su quanto l'app deve insistere, non un
/// dato di famiglia. E il rifiuto vale per ENTRAMBE le schermate — chi lo
/// scarta nella spesa ha capito di cosa si tratta, riproporglielo nei to-do
/// sarebbe la stessa richiesta due volte.
@MainActor
final class AlexaPromoStore: ObservableObject {
    static let shared = AlexaPromoStore()

    /// Le due preferenze sono per FAMIGLIA, non per dispositivo.
    ///
    /// `UserDefaults` sopravvive al logout: con una chiave globale, chi usciva
    /// da una famiglia con Alexa già collegata e rientrava con un account
    /// nuovo si portava dietro il «già collegata» del vecchio, e l'invito non
    /// compariva più su quel telefono. Vale anche per il rifiuto: «non
    /// mostrare più» detto in una famiglia non è una risposta data per
    /// un'altra.
    private static func dismissedKey(_ familyId: String) -> String { "alexa.promo.dismissed.\(familyId)" }
    private static func knownLinkedKey(_ familyId: String) -> String { "alexa.promo.knownLinked.\(familyId)" }

    @Published private(set) var shouldShow = false

    /// Esito della verifica, con la famiglia a cui si riferisce. Lo stato si
    /// chiede al massimo una volta per avvio e per famiglia: è una callable, e
    /// queste sono schermate che si aprono di continuo. La famiglia fa parte
    /// della memoria perché l'app non riparte al cambio account, e senza
    /// confrontarla si riuserebbe la decisione presa per quello precedente.
    ///
    /// Si conserva il RISULTATO e non un semplice «ho già chiesto»: le due
    /// schermate condividono questo store, e chi arriva secondo deve poter
    /// riaccendere l'invito che una `refresh` precoce — con la famiglia non
    /// ancora risolta — aveva spento.
    private var decision: (familyId: String, show: Bool)?

    private init() {}

    private func dismissed(_ familyId: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.dismissedKey(familyId))
    }

    /// Una volta che la famiglia risulta collegata non si torna indietro: il
    /// collegamento si può sciogliere, ma da Impostazioni, dove l'invito non
    /// serve più a nessuno.
    private func knownLinked(_ familyId: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.knownLinkedKey(familyId))
    }

    func refresh(familyId: String?) {
        // Famiglia non ancora risolta: non è un «no». Spegnere qui cancellava
        // l'invito già acceso dall'altra schermata, e la decisione memorizzata
        // impediva poi di riaccenderlo — è così che l'invito si vedeva nella
        // spesa e mai nei to-do.
        guard AlexaAvailability.isAvailable, let familyId, !familyId.isEmpty else { return }
        guard !dismissed(familyId), !knownLinked(familyId) else {
            shouldShow = false
            return
        }
        if let decision, decision.familyId == familyId {
            shouldShow = decision.show
            return
        }
        decision = (familyId, false)

        Task { @MainActor in
            do {
                let result = try await Functions.functions(region: "europe-west1")
                    .httpsCallable("getAlexaLinkStatus")
                    .call(["familyId": familyId])
                let dict = result.data as? [String: Any] ?? [:]
                let mine = dict["linked"] as? Bool == true
                let others = (dict["familyLinks"] as? [[String: Any]] ?? []).isEmpty == false
                if mine || others {
                    UserDefaults.standard.set(true, forKey: Self.knownLinkedKey(familyId))
                    decision = (familyId, false)
                    shouldShow = false
                } else {
                    decision = (familyId, true)
                    shouldShow = true
                }
            } catch {
                // Silenzio: un invito facoltativo non è motivo per mostrare un
                // errore in cima alla lista della spesa.
                KBLog.app.kbDebug("AlexaPromo: stato non leggibile, invito nascosto")
                // La decisione NON si memorizza: un errore di rete adesso non
                // deve nascondere l'invito per tutta la sessione.
                decision = nil
                shouldShow = false
            }
        }
    }

    func dismissForever() {
        guard let familyId = decision?.familyId else { return }
        UserDefaults.standard.set(true, forKey: Self.dismissedKey(familyId))
        decision = (familyId, false)
        shouldShow = false
    }
}

/// Testo dell'invito: cambia con la schermata da cui si vede.
enum AlexaPromoContext {
    case grocery
    case todo

    /// `LocalizedStringKey` e non `String`: un `Text(String)` NON passa dal
    /// catalogo, e il messaggio resterebbe in italiano per chi ha l'app in
    /// un'altra lingua. (Oggi l'invito si vede solo in italiano per via di
    /// `AlexaAvailability`, ma il giorno che la skill parlerà inglese questa
    /// riga non deve essere la cosa che se ne accorge per ultima.)
    var message: LocalizedStringKey {
        switch self {
        case .grocery:
            return "Puoi collegare Alexa a KidBox e dettare la lista della spesa agli Echo di casa: quello che dici compare qui e gli altri lo ricevono subito."
        case .todo:
            return "Puoi collegare Alexa a KidBox e dettare i promemoria agli Echo di casa: diventano to-do e la notifica arriva all'ora che hai detto."
        }
    }
}

struct AlexaPromoBanner: View {
    let context: AlexaPromoContext
    let onConnect: () -> Void

    @ObservedObject private var store = AlexaPromoStore.shared

    var body: some View {
        if store.shouldShow {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hifispeaker.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                    Text(context.message)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Collega", action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    // «Non mostrare più» e non «Annulla»: un invito che
                    // ricompare a ogni apertura della lista diventa un
                    // fastidio, e la scorciatoia resta comunque in
                    // Impostazioni → Alexa per chi cambia idea.
                    Button("Non mostrare più") { store.dismissForever() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                }
            }
            .padding(14)
            .background(KBTheme.bubbleTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
