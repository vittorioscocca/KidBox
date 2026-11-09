//
//  KeyVaultPromptView.swift
//  KidBox
//
//  «Proteggi la chiave della tua famiglia» (piano v2, Fase 2). Gemello di
//  `KeyVaultPrompt.jsx` sul web e di `KeyVaultPrompt.kt` su Android.
//
//  Se la cassaforte dell'utente non esiste la crea col codice di recupero; se
//  esiste (creata da un altro dispositivo o dal web) la apre col codice. Una
//  cassaforte per utente: il codice è lo stesso ovunque. Dopo: copia v2
//  verificata per ogni famiglia. La v1 non si tocca.
//
//  Passkey native e QR arrivano dopo: qui solo il codice.
//

import SwiftUI
import FirebaseAuth
import UniformTypeIdentifiers

struct KeyVaultPromptView: View {

    let uid: String
    let email: String?
    let familyIds: [String]
    let allowLater: Bool
    let onDone: () -> Void
    let onLater: () -> Void
    /// Da Impostazioni › Sicurezza: nuovo codice al posto del vecchio (serve la RK qui).
    var regenerate = false

    private enum Step { case loading, intro, code, confirm, open, done }

    @State private var step: Step = .loading
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var typedCode = ""
    @State private var copied = false
    @State private var code = FamilyKeyVaultCrypto.generateRecoveryCode()
    @State private var positions: [Int] = Array((0..<24).shuffled().prefix(4)).sorted()
    @State private var confirmChars = ["", "", "", ""]

    private var canonical: String? { FamilyKeyVaultCrypto.normalizeRecoveryCode(code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    content
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                if allowLater && step != .done && step != .loading {
                    ToolbarItem(placement: .cancellationAction) {
                        if regenerate {
                            Button("Annulla") { onLater() }.disabled(busy)
                        } else {
                            Button("Più tardi") { onLater() }.disabled(busy)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .task { await load() }
    }

    // MARK: passi

    @ViewBuilder
    private var content: some View {
        switch step {
        case .loading:
            ProgressView().padding(.top, 60)

        case .intro:
            icon("lock.shield")
            title("Proteggi la chiave della tua famiglia")
            lead("Documenti, password e foto di KidBox sono cifrati con una chiave che ha solo la tua famiglia. Per ritrovarla su un nuovo telefono o sul computer, salva un codice di recupero. Nemmeno KidBox può aprirla.")
            small("Di solito non ti servirà: se hai ancora un dispositivo o un familiare con KidBox, rientri da lì.")
            errorView
            primary("Crea il codice di recupero") { step = .code }

        case .code:
            title("Il tuo codice di recupero")
            lead("Salvalo adesso: lo vedi solo questa volta. Vale per tutte le tue famiglie e su tutti i dispositivi.")
            Text(code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 12) {
                Button { copyCode() } label: {
                    Label(copied ? String(localized: "Copiato") : String(localized: "Copia"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                ShareLink(item: fileText) {
                    Label("Salva o stampa", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            Text("Se perdi questo codice e tutti i tuoi dispositivi, e nessun familiare ha l'app, i dati cifrati non si possono recuperare.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            small("Stampalo o salvalo nel gestore di password del telefono. Non salvarlo nelle Password di KidBox: si aprono con la stessa chiave che questo codice serve a ritrovare.")
            primary("Ho salvato il codice") { error = nil; step = .confirm }

        case .confirm:
            title("Conferma il codice")
            lead("Scrivi i caratteri del codice nelle posizioni indicate.")
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text("N. \(positions[i] + 1)").font(.caption).foregroundStyle(.secondary)
                        TextField(String(), text: Binding(
                            get: { confirmChars[i] },
                            set: { confirmChars[i] = String($0.suffix(1)).uppercased() }
                        ))
                        .font(.system(.title2, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 52, height: 52)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            errorView
            primary(busy ? "Creazione…" : "Conferma",
                    disabled: busy || confirmChars.contains(where: \.isEmpty) || canonical == nil) {
                Task { await confirmCreate() }
            }
            Button("Indietro") { error = nil; step = .code }.disabled(busy)

        case .open:
            icon("lock.shield")
            title("Apri la cassaforte della famiglia")
            if let notice { noticeView(notice) }
            lead("Su questo dispositivo serve una volta sola: scrivi il codice di recupero che hai salvato.")
            TextField(String("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"), text: $typedCode)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .padding(12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            errorView
            primary(busy ? "Apertura…" : "Apri",
                    disabled: busy || FamilyKeyVaultCrypto.normalizeRecoveryCode(typedCode) == nil) {
                Task { await openWithCode() }
            }
            small("Hai perso il codice? Se hai ancora un dispositivo o un familiare con KidBox, rientri da lì.")

        case .done:
            icon("checkmark.seal.fill")
            title("Fatto")
            if let notice { noticeView(notice) }
            lead("La chiave della tua famiglia è protetta. Nemmeno KidBox può aprirla.")
            primary("Continua") { onDone() }
        }
    }

    // MARK: azioni

    private func load() async {
        if regenerate { step = .code; return }
        do {
            step = try await FamilyKeyVault.slotCount(uid: uid) > 0 ? .open : .intro
        } catch {
            self.error = String(localized: "Qualcosa non ha funzionato. Riprova.")
            step = .intro
        }
    }

    private func confirmCreate() async {
        error = nil
        let norm: (String) -> String = {
            $0.uppercased().replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1")
        }
        guard let canonical else { return }
        let chars = Array(canonical)
        guard positions.indices.allSatisfy({ String(chars[positions[$0]]) == norm(confirmChars[$0]) }) else {
            error = String(localized: "Non corrisponde: ricontrolla il codice che hai salvato.")
            return
        }
        busy = true
        defer { busy = false }
        do {
            if regenerate {
                try await FamilyKeyVault.replaceRecoveryCode(uid: uid, recoveryCode: code)
                notice = String(localized: "Il codice precedente non vale più: d'ora in poi usa quello nuovo.")
                step = .done
                return
            }
            try await FamilyKeyVault.createVault(uid: uid, recoveryCode: code)
            await FamilyKeyVault.syncFamilyKeysV2(uid: uid, familyIds: familyIds)
            step = .done
        } catch FamilyKeyVault.OpenError.exists {
            notice = String(localized: "La tua cassaforte è stata appena creata da un altro dispositivo: aprila con quel codice.")
            step = .open
        } catch {
            KBLog.security.kbError("Vault: creazione fallita \(error.localizedDescription)")
            self.error = String(localized: "Qualcosa non ha funzionato. Riprova.")
        }
    }

    private func openWithCode() async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await FamilyKeyVault.openWithRecoveryCode(uid: uid, recoveryCode: typedCode)
            await FamilyKeyVault.syncFamilyKeysV2(uid: uid, familyIds: familyIds)
            notice = nil
            step = .done
        } catch FamilyKeyVault.OpenError.wrongSecret {
            error = String(localized: "Codice non valido: controlla di averlo scritto tutto e senza errori.")
        } catch {
            KBLog.security.kbError("Vault: apertura fallita \(error.localizedDescription)")
            self.error = String(localized: "Qualcosa non ha funzionato. Riprova.")
        }
    }

    /// Negli appunti solo su questo dispositivo (niente Appunti universali) e per due minuti.
    private func copyCode() {
        #if canImport(UIKit)
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
        #endif
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private var fileText: String {
        [
            String(localized: "KidBox — codice di recupero della chiave di famiglia"),
            code,
            email ?? "",
            String(localized: "Se perdi questo codice e tutti i tuoi dispositivi, e nessun familiare ha l'app, i dati cifrati non si possono recuperare."),
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // MARK: pezzi

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 44)).foregroundStyle(.tint).padding(.top, 8)
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.title2.bold()).multilineTextAlignment(.center)
    }

    private func lead(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.body).multilineTextAlignment(.center)
    }

    private func small(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    private func noticeView(_ text: String) -> some View {
        Text(text).font(.callout).padding(12).frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var errorView: some View {
        if let error { Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center) }
    }

    private func primary(_ key: LocalizedStringKey, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }
}

// MARK: - Promemoria all'avvio

/// Compare solo con `config/keyVault` acceso per questo utente e se il
/// dispositivo non ha ancora la chiave personale. «Più tardi» vale fino alla
/// prossima apertura dell'app; con `enforce` non c'è. Non blocca niente: finché
/// c'è la v1 la chiave di famiglia arriva da lì.
private struct KeyVaultGateModifier: ViewModifier {
    let familyIds: [String]
    @State private var presented: (uid: String, enforce: Bool)?
    @MainActor private static var laterThisLaunch = Set<String>()

    func body(content: Content) -> some View {
        content
            .task(id: familyIds.sorted().joined(separator: ",")) { await check() }
            .sheet(isPresented: Binding(get: { presented != nil }, set: { if !$0 { presented = nil } })) {
                if let p = presented {
                    KeyVaultPromptView(
                        uid: p.uid,
                        email: Auth.auth().currentUser?.email,
                        familyIds: familyIds,
                        allowLater: !p.enforce,
                        onDone: { presented = nil },
                        onLater: {
                            Self.laterThisLaunch.insert(p.uid)
                            presented = nil
                        }
                    )
                }
            }
    }

    private func check() async {
        guard presented == nil, !familyIds.isEmpty,
              let uid = Auth.auth().currentUser?.uid, !uid.isEmpty,
              FamilyKeyVault.loadRK(uid: uid) == nil else { return }
        let flags = await FamilyKeyVault.flags(uid: uid)
        guard flags.active, flags.enforce || !Self.laterThisLaunch.contains(uid) else { return }
        // Lascia finire l'avvio (onboarding, inviti, popup) prima di chiedere.
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled, FamilyKeyVault.loadRK(uid: uid) == nil else { return }
        presented = (uid, flags.enforce)
    }
}

extension View {
    /// Promemoria della cassaforte v2 (piano, sezione 4 ter).
    func keyVaultGate(familyIds: [String]) -> some View {
        modifier(KeyVaultGateModifier(familyIds: familyIds))
    }
}
