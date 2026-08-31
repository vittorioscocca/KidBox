//
//  NonOwnerUpgradeNotice.swift
//  KidBox
//
//  Messaggio "solo chi ha creato la famiglia può abbonarsi".
//
//  Compare SOLO al tocco di un pulsante di acquisto, mai come testo fisso
//  nell'interfaccia: i pulsanti restano tutti al loro posto per ogni membro —
//  nascondere l'unico pulsante che spiegava il piano lasciava senza risposta la
//  domanda "perché non posso abbonarmi?".
//
//  Gemello del dialog Android (subscription_owner_managed_title/body).
//

import SwiftUI

extension View {

    /// Avviso modale per i membri che toccano un pulsante di abbonamento.
    func ownerOnlyAlert(isPresented: Binding<Bool>) -> some View {
        alert("Piano gestito dal creatore", isPresented: isPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Solo chi ha creato la famiglia può attivare o cambiare un abbonamento. Chiedi al creatore di passare a un piano superiore se serve più spazio o funzioni AI.")
        }
    }
}
