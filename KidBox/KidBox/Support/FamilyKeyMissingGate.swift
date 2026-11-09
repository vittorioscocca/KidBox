//
//  FamilyKeyMissingGate.swift
//  KidBox
//
//  Avviso, una volta per schermata, che manca la chiave della famiglia.
//
//  Perché all'ingresso e non sul singolo errore: le decifrature sparse in
//  Documenti, Wallet, Chat e Foto falliscono tutte per la stessa ragione, e
//  parecchie scartano l'esito in silenzio (`try? NoteCryptoService.decryptString`
//  in ChatViewModel, `try? WalletCryptoService.decryptString` nei campi del
//  Wallet), lasciando l'utente davanti a contenuti vuoti senza spiegazione.
//  Controllare la condizione a monte le copre tutte insieme, senza dover
//  modificare ogni punto di cattura.
//
//  Gemello di `FamilyKeyMissingGate` su Android.
//

import SwiftUI
import FirebaseAuth

private struct FamilyKeyMissingGateModifier: ViewModifier {

    let familyId: String

    @State private var showAlert = false
    /// Una volta sola per apparizione della schermata: `ensureFamilyKeyAvailable`
    /// fa una lettura di rete e l'avviso non deve ricomparire a ogni ridisegno.
    @State private var didCheck = false
    /// Cassaforte v2 accesa per questo utente: allora l'avviso offre anche il
    /// QR per farsi mandare la chiave (piano v2, sezione 3.2).
    @State private var canReceive = false
    @State private var showReceive = false

    func body(content: Content) -> some View {
        content
            .task(id: familyId) {
                guard !didCheck, !familyId.isEmpty else { return }
                guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
                didCheck = true

                let available = await FamilyKeyEscrowService.ensureFamilyKeyAvailable(
                    familyId: familyId,
                    userId: uid
                )
                if !available {
                    KBLog.security.kbError("FamilyKeyMissingGate: no vault key familyId=\(familyId)")
                    canReceive = await FamilyKeyVault.flags(uid: uid).active
                    showAlert = true
                }
            }
            .alert(FamilyKeyMissing.title, isPresented: $showAlert) {
                if canReceive {
                    Button("Ricevi la chiave con un QR") { showReceive = true }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(canReceive ? FamilyKeyMissing.messageWithQR : FamilyKeyMissing.message)
            }
            .sheet(isPresented: $showReceive) {
                KeyVaultPromptView(
                    uid: Auth.auth().currentUser?.uid ?? "",
                    email: Auth.auth().currentUser?.email,
                    familyIds: [familyId],
                    allowLater: true,
                    onDone: { showReceive = false },
                    onLater: { showReceive = false },
                    receive: true
                )
            }
    }
}

extension View {
    /// Mostra l'avviso di chiave mancante all'apertura della schermata.
    ///
    /// Da applicare alle aree che mostrano contenuti cifrati con la master key
    /// di famiglia: Documenti, Wallet, Chat, Foto.
    func familyKeyMissingGate(familyId: String) -> some View {
        modifier(FamilyKeyMissingGateModifier(familyId: familyId))
    }
}
