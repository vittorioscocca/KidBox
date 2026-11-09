//
//  KeyHandoffScanView.swift
//  KidBox
//
//  Impostazioni › Sicurezza › «Inquadra un QR»: il lato di chi MANDA la chiave
//  (KeyHandoff). Inquadra il QR del browser, del dispositivo nuovo o del
//  familiare, dice cosa sta per mandare e a chi, e manda solo dopo il sì.
//

import SwiftUI
import FirebaseAuth

struct KeyHandoffScanView: View {

    let familyIds: [String]
    let onClose: () -> Void

    private enum Phase { case scanning, checking, confirm(KeyHandoff.Target), sending, sent, failed(String) }

    @State private var phase: Phase = .scanning
    @State private var scanId = UUID()

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Inquadra un QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { onClose() } }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .scanning:
            VStack(spacing: 16) {
                QRCodeScannerView { code in Task { await check(code) } }
                    .id(scanId)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text("Inquadra il QR mostrato dal computer, da un altro tuo dispositivo o dal telefono di un familiare.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding()

        case .checking, .sending:
            ProgressView().padding(.top, 80)

        case .confirm(let t):
            VStack(spacing: 18) {
                Image(systemName: "key.horizontal.fill").font(.system(size: 44)).foregroundStyle(.tint)
                switch t.kind {
                case .rk:
                    Text("Mandare la tua chiave a «\(t.receiver)»?")
                        .font(.title3.bold()).multilineTextAlignment(.center)
                    Text("Quel dispositivo potrà aprire i dati cifrati di tutte le tue famiglie. Conferma solo se il QR è sul tuo computer o su un tuo dispositivo.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                case .familyKey(_, let familyName):
                    Text("Mandare la chiave di «\(familyName)» a \(t.receiver)?")
                        .font(.title3.bold()).multilineTextAlignment(.center)
                    Text("Così potrà leggere documenti, password e foto della famiglia anche se non aveva la chiave.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                Button {
                    Task { await send(t) }
                } label: {
                    Text("Manda la chiave").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button("Annulla") { onClose() }
            }
            .padding(24)

        case .sent:
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("Chiave mandata").font(.title3.bold())
                Text("L'altro dispositivo la riceve chiusa e la apre da solo: nemmeno KidBox può leggerla.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Fatto") { onClose() }.buttonStyle(.borderedProminent)
            }
            .padding(24)

        case .failed(let message):
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Riprova") { scanId = UUID(); phase = .scanning }.buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    private func check(_ code: String) async {
        phase = .checking
        do {
            phase = .confirm(try await KeyHandoff.prepare(qr: code, uid: uid, familyIds: familyIds))
        } catch KeyHandoff.HandoffError.badQR {
            phase = .failed(String(localized: "Questo non è un QR di KidBox per la chiave."))
        } catch KeyHandoff.HandoffError.expired {
            phase = .failed(String(localized: "Il QR è scaduto o è già stato usato: chiedine uno nuovo."))
        } catch KeyHandoff.HandoffError.nothingToSend {
            phase = .failed(String(localized: "Da qui non c'è una chiave da mandare a chi mostra il QR: deve essere il tuo account o un membro della tua famiglia."))
        } catch {
            KBLog.security.kbError("KeyHandoff: controllo fallito \(String(describing: error))")
            phase = .failed(String(localized: "Qualcosa non ha funzionato. Riprova."))
        }
    }

    private func send(_ t: KeyHandoff.Target) async {
        phase = .sending
        do {
            try await KeyHandoff.deliver(t, uid: uid)
            phase = .sent
        } catch {
            KBLog.security.kbError("KeyHandoff: invio fallito \(String(describing: error))")
            phase = .failed(String(localized: "Il QR è scaduto o è già stato usato: chiedine uno nuovo."))
        }
    }
}
