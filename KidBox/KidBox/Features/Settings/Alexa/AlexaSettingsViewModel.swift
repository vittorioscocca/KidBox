//
//  AlexaSettingsViewModel.swift
//  KidBox
//

import Foundation
import FirebaseFunctions
import Combine

/// Stato del collegamento fra questo account KidBox e la skill Alexa.
///
/// Perché un codice da dettare e non un login dentro la skill: l'account
/// linking di Alexa vuole un authorization server OAuth2 con una sua pagina di
/// login, e i nostri account nascono in gran parte da Google e Apple — quella
/// pagina dovrebbe rifare il giro completo di entrambi i provider dentro la
/// webview di Amazon. Qui invece l'utente è GIÀ autenticato nell'app: il codice
/// trasporta quell'identità verso Alexa senza chiedere di nuovo le credenziali,
/// e il provider di login non c'entra più nulla.
@MainActor
final class AlexaSettingsViewModel: ObservableObject {

    // MARK: - Stato

    enum LinkState: Equatable {
        case unknown
        case linked(since: Date?)
        case notLinked
    }

    /// Cosa lega il membro ad Alexa. Sono cose diverse: l'account dà accesso
    /// alla lista, la voce dà solo l'attribuzione di chi ha dettato.
    enum LinkKind: String, Equatable {
        case account
        case voice
    }

    /// Un collegamento della famiglia: serve a far vedere agli altri membri che
    /// Alexa è già accoppiata, invece di proporre loro un accoppiamento da zero.
    struct FamilyLink: Equatable, Identifiable {
        let uid: String
        let name: String?
        let isMe: Bool
        let kind: LinkKind
        let linkedAt: Date?

        var id: String { "\(uid)-\(kind.rawValue)" }

        /// Nome da mostrare quando il membro non ha un nome impostato.
        var displayName: String {
            if let name, !name.isEmpty { return name }
            return String(localized: "Un membro della famiglia")
        }
    }

    @Published private(set) var linkState: LinkState = .unknown
    /// La mia voce è riconosciuta e associata a me. Senza, quello che detto
    /// risulta aggiunto da chi ha collegato l'account.
    @Published private(set) var voiceLinked = false
    /// Collegamenti di ALTRI membri. Il proprio non c'è: lo racconta `linkState`.
    @Published private(set) var otherLinks: [FamilyLink] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var errorText: String?

    /// Codice attivo, già formattato per la lettura ad alta voce ("482 915").
    @Published private(set) var pairingCode: String?
    /// Secondi che restano prima della scadenza: sotto zero il codice sparisce.
    @Published private(set) var secondsLeft: Int = 0

    private let functions = Functions.functions(region: "europe-west1")
    private var expiresAt: Date?
    private var tickTask: Task<Void, Never>?
    /// Famiglia con cui si è caricata la schermata: il polling la riusa senza
    /// doversela far ripassare dalla view a ogni giro.
    private var familyId: String?

    deinit { tickTask?.cancel() }

    // MARK: - Lettura stato

    func load(familyId: String?) {
        guard !isLoading else { return }
        guard let familyId, !familyId.isEmpty else {
            errorText = "Nessuna famiglia attiva."
            linkState = .notLinked
            return
        }
        self.familyId = familyId
        isLoading = true
        errorText = nil

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let result = try await functions
                    .httpsCallable("getAlexaLinkStatus")
                    .call(["familyId": familyId])
                applyStatus(result.data)
            } catch {
                KBLog.app.kbError("AlexaSettings.load failed: \(error.localizedDescription)")
                errorText = "Non riesco a leggere lo stato del collegamento."
            }
        }
    }

    private func applyStatus(_ data: Any?) {
        guard let dict = data as? [String: Any] else {
            linkState = .notLinked
            otherLinks = []
            return
        }

        // I collegamenti degli altri membri si leggono comunque, anche quando il
        // proprio non c'è: è proprio quello il caso in cui servono.
        let raw = dict["familyLinks"] as? [[String: Any]] ?? []
        otherLinks = raw.compactMap { entry in
            guard let uid = entry["uid"] as? String, !uid.isEmpty else { return nil }
            guard (entry["isMe"] as? Bool) != true else { return nil }
            // `linkedAt` arriva in millisecondi: è il formato con cui la
            // function serializza i Timestamp Firestore.
            let at = (entry["linkedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            let kind = LinkKind(rawValue: entry["kind"] as? String ?? "account") ?? .account
            return FamilyLink(uid: uid, name: entry["name"] as? String, isMe: false, kind: kind, linkedAt: at)
        }
        .sorted { ($0.linkedAt ?? .distantPast) < ($1.linkedAt ?? .distantPast) }

        voiceLinked = dict["voiceLinked"] as? Bool == true

        guard dict["linked"] as? Bool == true else {
            linkState = .notLinked
            return
        }

        let since = (dict["linkedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        linkState = .linked(since: since)

        // Il codice si toglie solo quando non resta niente da legare: con
        // l'account collegato ma la voce no, lo stesso codice serve ancora.
        if voiceLinked { clearCode() }
    }

    // MARK: - Generazione codice

    func generateCode(familyId: String?) {
        guard let familyId, !familyId.isEmpty else {
            errorText = "Nessuna famiglia attiva."
            return
        }
        self.familyId = familyId
        guard !isGenerating else { return }
        isGenerating = true
        errorText = nil

        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let result = try await functions
                    .httpsCallable("createAlexaPairingCode")
                    .call(["familyId": familyId])

                guard let dict = result.data as? [String: Any],
                      let code = dict["code"] as? String,
                      let expiresMs = dict["expiresAt"] as? Double else {
                    errorText = "Risposta inattesa dal server."
                    return
                }

                pairingCode = formatted(code)
                expiresAt = Date(timeIntervalSince1970: expiresMs / 1000)
                startTicking()
            } catch {
                KBLog.app.kbError("AlexaSettings.generateCode failed: \(error.localizedDescription)")
                errorText = "Non riesco a generare il codice. Riprova."
            }
        }
    }

    /// "482915" → "482 915": a gruppi si detta senza perdere il segno.
    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }

    /// Conto alla rovescia + polling dello stato: l'app non ha modo di sapere
    /// quando l'utente ha finito di parlare all'Echo, quindi finché il codice è
    /// vivo si richiede lo stato ogni pochi secondi e la schermata si aggiorna
    /// da sola nel momento in cui il collegamento nasce.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            var elapsed = 0
            while !Task.isCancelled {
                guard let self, let expiresAt = self.expiresAt else { return }

                let remaining = Int(expiresAt.timeIntervalSinceNow.rounded())
                self.secondsLeft = max(0, remaining)
                if remaining <= 0 {
                    self.clearCode()
                    return
                }

                if elapsed > 0, elapsed % 5 == 0 {
                    await self.pollStatus()
                    if case .linked = self.linkState, self.voiceLinked { return }
                }

                try? await Task.sleep(for: .seconds(1))
                elapsed += 1
            }
        }
    }

    /// Come `load()` ma silenzioso: durante il polling un errore di rete non
    /// deve riempire la schermata di avvisi mentre l'utente sta parlando.
    private func pollStatus() async {
        guard let familyId, !familyId.isEmpty else { return }
        guard let result = try? await functions
            .httpsCallable("getAlexaLinkStatus")
            .call(["familyId": familyId]) else { return }
        applyStatus(result.data)
    }

    private func clearCode() {
        tickTask?.cancel()
        tickTask = nil
        pairingCode = nil
        expiresAt = nil
        secondsLeft = 0
    }

    // MARK: - Scollegamento

    func unlink() {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil

        Task { @MainActor in
            defer { isLoading = false }
            do {
                _ = try await functions.httpsCallable("unlinkAlexa").call()
                linkState = .notLinked
                clearCode()
            } catch {
                KBLog.app.kbError("AlexaSettings.unlink failed: \(error.localizedDescription)")
                errorText = "Non riesco a scollegare Alexa. Riprova."
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }
}
