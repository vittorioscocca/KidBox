//
//  SecuritySettingsView.swift
//  KidBox
//
//  Impostazioni › Sicurezza: la cassaforte della chiave di famiglia (piano v2,
//  Fase 2). Stato su questo dispositivo, metodi per riaprirla altrove (codice
//  di recupero, passkey), «Rigenera codice» da qui se il dispositivo ha la RK.
//

import SwiftUI
import FirebaseAuth

struct SecuritySettingsView: View {

    let familyIds: [String]

    @State private var slots: [FamilyKeyVault.Slot] = []
    @State private var hasRK = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var sheet: SheetKind?
    @State private var showScan = false

    private enum SheetKind: String, Identifiable { case open, regenerate, passkey, receive; var id: String { rawValue } }

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }
    private var recovery: FamilyKeyVault.Slot? { slots.first { $0.type == "recoveryCode" } }
    private var passkeys: [FamilyKeyVault.Slot] { slots.filter { $0.type == "passkey" } }

    var body: some View {
        List {
            Section {
                statusRow
            } footer: {
                Text("Documenti, password e foto sono cifrati con una chiave che ha solo la tua famiglia. Qui scegli come ritrovarla su un nuovo dispositivo. Nemmeno KidBox può aprirla.")
            }

            if loaded && !slots.isEmpty {
                Section {
                    if let recovery {
                        HStack {
                            Label("Codice di recupero", systemImage: "key.horizontal")
                            Spacer()
                            if let d = recovery.updatedAt ?? recovery.createdAt {
                                Text(d, format: .dateTime.day().month().year())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(passkeys) { p in
                        Label {
                            if let label = p.label, !label.isEmpty {
                                Text(verbatim: label)
                            } else {
                                Text("Passkey")
                            }
                        } icon: {
                            Image(systemName: "person.badge.key")
                        }
                    }
                } header: {
                    Text("Modi per aprire la cassaforte")
                }
            }

            if loaded {
                Section {
                    if slots.isEmpty || !hasRK {
                        Button {
                            sheet = .open
                        } label: {
                            if slots.isEmpty {
                                Text("Crea il codice di recupero")
                            } else {
                                Text("Apri la cassaforte su questo dispositivo")
                            }
                        }
                    }
                    if hasRK && !slots.isEmpty {
                        Button("Aggiungi una passkey") { sheet = .passkey }
                    }
                    if hasRK && recovery != nil {
                        Button("Rigenera codice di recupero") { sheet = .regenerate }
                    }
                } footer: {
                    if hasRK && recovery != nil {
                        Text("Se hai perso il codice ma hai ancora questo dispositivo, creane uno nuovo: quello vecchio smette di valere.")
                    }
                }
            }
            if loaded {
                Section {
                    Button {
                        showScan = true
                    } label: {
                        Label("Inquadra un QR", systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        sheet = .receive
                    } label: {
                        Label("Ricevi la chiave con un QR", systemImage: "qrcode")
                    }
                } footer: {
                    Text("«Inquadra un QR» dà la chiave al computer, a un tuo nuovo dispositivo o a un familiare. «Ricevi la chiave con un QR» serve se qui manca: mostra un QR da inquadrare con un altro tuo dispositivo o con il telefono di un familiare.")
                }
            }
        }
        .navigationTitle("Sicurezza")
        .sheet(isPresented: $showScan) {
            KeyHandoffScanView(familyIds: familyIds) { showScan = false }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $sheet) { kind in
            KeyVaultPromptView(
                uid: uid,
                email: Auth.auth().currentUser?.email,
                familyIds: familyIds,
                allowLater: true,
                onDone: { sheet = nil; Task { await reload() } },
                onLater: { sheet = nil },
                regenerate: kind == .regenerate,
                addPasskey: kind == .passkey,
                receive: kind == .receive
            )
        }
    }

    @ViewBuilder private var statusRow: some View {
        if !loaded {
            HStack { ProgressView(); Text("Controllo…").foregroundStyle(.secondary) }
        } else if loadFailed {
            Label("Non riesco a leggere lo stato. Controlla la connessione.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if slots.isEmpty {
            Label("Chiave non ancora protetta", systemImage: "lock.open")
                .foregroundStyle(.orange)
        } else if hasRK {
            Label("Chiave protetta su questo dispositivo", systemImage: "lock.shield.fill")
                .foregroundStyle(.green)
        } else {
            Label("Cassaforte da aprire su questo dispositivo", systemImage: "lock")
                .foregroundStyle(.orange)
        }
    }

    private func reload() async {
        guard !uid.isEmpty else { return }
        hasRK = FamilyKeyVault.loadRK(uid: uid) != nil
        do {
            slots = try await FamilyKeyVault.listSlots(uid: uid)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        loaded = true
    }
}
