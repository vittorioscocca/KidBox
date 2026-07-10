//
//  SupportChatViewModel.swift
//  KidBox
//

import Combine
import FirebaseAuth
import Foundation
import SwiftUI

struct SupportAttachedImage: Identifiable, Equatable {
    let id: UUID
    let data: Data
}

struct SupportMessage: Identifiable, Equatable {
    let id: String
    let role: String
    let text: String
    var imageDatas: [Data] = []
}

@MainActor
final class SupportChatViewModel: ObservableObject {
    @Published var messages: [SupportMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""
    @Published var attachedImages: [SupportAttachedImage] = []
    @Published var detectedType: String?
    @Published var showSubmitConfirm = false
    @Published var ticketSent = false
    @Published var errorMessage: String?

    private let ticketId = UUID().uuidString

    private static let roleUser = "user"
    private static let roleAssistant = "assistant"
    private static let purposeSupport = "support"
    private static let typeQuestion = "question"
    private static let typeBug = "bug"
    private static let titleMaxLen = 120
    private static let summaryMaxLen = 2000
    private static let defaultTicketTitle = "Richiesta supporto KidBox"

    private static let supportSystemPrompt = """
    Sei l'assistente di supporto di KidBox, app di gestione familiare.
    Conosci tutte le funzionalità: famiglia, bambini, calendario, note, documenti,
    spese, farmaci, visite mediche, posizione, chat, animali, garage/veicoli,
    casa, viaggi, portafoglio, password, routine, AI assistente.
    Nel Wallet (portafoglio) c'è una sezione "Documenti" dedicata ai documenti
    d'identità (Tessera Sanitaria, CIE, Carta d'identità cartacea, Patente,
    Passaporto, Codice Fiscale): si aggiungono scansionando il documento con la
    fotocamera (rilevamento bordi automatico, fronte+retro, 2-3 pagine per il
    passaporto) oppure collegando un file già caricato nella sezione Documenti
    generale (in quel caso il file viene spostato nella cartella "Documenti
    d'identità" di Documenti, senza duplicarlo). L'app prova a leggere da sola
    nome e cognome del titolare, data e luogo di nascita, numero documento,
    Codice Fiscale, data di rilascio e di scadenza; l'utente può sempre
    correggerli a mano dal pulsante "Modifica" nel dettaglio. Per la patente
    legge il numero dal fronte e, dal retro, la tabella con categoria/rilascio/
    scadenza per ogni patente posseduta (A, B, C...); non ha Codice Fiscale.
    La Tessera Sanitaria mostra il Codice Fiscale anche come barcode
    ingrandibile a schermo intero (utile per farlo scansionare allo sportello);
    la CIE invece mostra il Codice Fiscale solo come testo, senza barcode. Per
    patente, carta d'identità, CIE e Codice Fiscale c'è un pulsante per vedere
    le foto vere del documento a schermo intero (fronte/retro). Se il
    documento ha una scadenza, si può attivare un promemoria "avvisami una
    settimana prima". Con il piano Max è disponibile anche una lettura più
    precisa assistita dall'AI (consuma qualche messaggio in più, il costo è
    mostrato prima di confermare). Tutti questi dati (Codice Fiscale, nome,
    date, numero) sono cifrati con la chiave della famiglia, sia sul
    dispositivo sia su Firebase. Dalla sezione Documenti del Wallet si possono
    anche selezionare più documenti ed eliminarli insieme, o eliminarne uno
    singolo tenendo premuto sulla card.
    Rispondi in italiano, in modo chiaro e conciso.
    Se l'utente descrive un problema tecnico o un bug, chiedi conferma e poi
    imposta il tipo su "bug". Se suggerisce una feature, tipo "suggestion".
    Altrimenti "question". Quando capisci il tipo, includi nel tuo messaggio
    il tag nascosto [TYPE:bug] o [TYPE:suggestion] o [TYPE:question].
    NON chiedere MAI all'utente di esportare, copiare o inviare manualmente i log dall'app o dalle impostazioni:
    KidBox allega automaticamente all'invio del ticket gli stessi log diagnostici usati per i crash report su Firebase.
    Per i bug puoi spiegare che i log tecnici verranno inclusi automaticamente quando l'utente confermerà l'invio della segnalazione.
    Quando il ticket è pronto per l'invio e l'utente ha confermato, includi [SUBMIT] nel messaggio.
    """

    func addImage(data: Data) {
        guard attachedImages.count < SupportImageEncoder.maxImages else { return }
        guard !attachedImages.contains(where: { $0.data == data }) else { return }
        attachedImages.append(SupportAttachedImage(id: UUID(), data: data))
    }

    func removeImage(id: UUID) {
        attachedImages.removeAll { $0.id == id }
    }

    func sendMessage(text: String, imageDatas: [Data]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = Array(imageDatas.prefix(SupportImageEncoder.maxImages))
        guard !trimmed.isEmpty || !images.isEmpty else { return }

        Task {
            guard let familyId = currentFamilyId else {
                errorMessage = "Seleziona una famiglia attiva."
                return
            }

            let userMessage = SupportMessage(
                id: UUID().uuidString,
                role: Self.roleUser,
                text: trimmed,
                imageDatas: images,
            )
            messages.append(userMessage)
            isLoading = true
            inputText = ""
            attachedImages = []
            errorMessage = nil

            do {
                let apiMessages = buildApiMessages()
                let response = try await AIService.shared.sendMessages(
                    messages: apiMessages,
                    systemPrompt: Self.supportSystemPrompt,
                    purpose: Self.purposeSupport,
                )
                let parsed = SupportAssistantReplyParser.parse(response.reply)
                messages.append(
                    SupportMessage(
                        id: UUID().uuidString,
                        role: Self.roleAssistant,
                        text: parsed.displayText,
                    ),
                )
                if let type = parsed.type {
                    detectedType = type
                }
                if parsed.requestSubmit {
                    showSubmitConfirm = true
                }
                isLoading = false
            } catch let err as AIServiceError {
                isLoading = false
                errorMessage = err.errorDescription
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func confirmSubmit() {
        Task {
            guard let familyId = currentFamilyId else {
                errorMessage = "Seleziona una famiglia attiva."
                return
            }

            isLoading = true
            showSubmitConfirm = false
            errorMessage = nil

            do {
                let type = detectedType ?? Self.typeQuestion
                var conversation: [SupportConversationMessagePayload] = []
                for msg in messages {
                    let content: Any
                    if msg.imageDatas.isEmpty {
                        content = msg.text
                    } else {
                        content = buildMultimodalContent(text: msg.text, imageDatas: msg.imageDatas)
                    }
                    conversation.append(
                        SupportConversationMessagePayload(role: msg.role, content: content),
                    )
                }

                let imageBase64 = encodeImagesForTicket()
                let logsTrimmed = KBFileLogger.shared.readLogs().trimmingCharacters(in: .whitespacesAndNewlines)
                let rawLogs: String? = (type == Self.typeBug && !logsTrimmed.isEmpty)
                    ? SupportTicketFirestorePayload.truncateLogs(logsTrimmed)
                    : nil

                let title = ticketTitle(from: messages)
                let summary = ticketSummary(from: messages, fallback: title)

                // ── Pre-flight diagnostics ─────────────────────────────
                let diagEmail = Auth.auth().currentUser?.email ?? "(nil)"
                let diagUid   = Auth.auth().currentUser?.uid   ?? "(nil)"
                KBLog.app.kbInfo("""
                SupportChatVM confirmSubmit pre-flight \
                ticketId=\(ticketId) \
                familyId=\(familyId) \
                uid=\(diagUid) \
                email=\(diagEmail) \
                type=\(type) \
                titleLen=\(title.count) \
                summaryLen=\(summary.count) \
                images=\(imageBase64.count) \
                hasLogs=\(rawLogs != nil)
                """)
                guard !familyId.isEmpty else {
                    throw NSError(domain: "SupportTicket", code: 400,
                                  userInfo: [NSLocalizedDescriptionKey: "Famiglia non trovata. Riprova dopo il login."])
                }
                guard !title.isEmpty else {
                    throw NSError(domain: "SupportTicket", code: 400,
                                  userInfo: [NSLocalizedDescriptionKey: "Scrivi almeno un messaggio prima di inviare."])
                }
                // ──────────────────────────────────────────────────────

                let payload = try SupportTicketSubmitPayload.make(
                    id: ticketId,
                    familyId: familyId,
                    type: type,
                    title: title,
                    summary: summary,
                    conversation: conversation,
                    imagesBase64: imageBase64,
                    rawLogs: rawLogs,
                )
                _ = try await SupportTicketRemoteStore.shared.submit(payload)
                isLoading = false
                ticketSent = true
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissSubmitConfirm() {
        showSubmitConfirm = false
    }

    private func ticketTitle(from messages: [SupportMessage]) -> String {
        guard let text = messages.first(where: { $0.role == Self.roleUser })?.text else {
            return Self.defaultTicketTitle
        }
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        let trimmed = firstLine.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if trimmed.isEmpty { return Self.defaultTicketTitle }
        return String(trimmed.prefix(Self.titleMaxLen))
    }

    private func ticketSummary(from messages: [SupportMessage], fallback: String) -> String {
        guard let text = messages.last(where: { $0.role == Self.roleAssistant })?.text else {
            return fallback
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return String(trimmed.prefix(Self.summaryMaxLen))
    }

    private var currentFamilyId: String? {
        let id = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
            .string(forKey: "activeFamilyId") ?? ""
        return id.isEmpty ? nil : id
    }

    private func buildApiMessages() -> [AIMessagePayload] {
        messages.map { msg in
            let content: Any
            if msg.role == Self.roleUser, !msg.imageDatas.isEmpty {
                content = buildMultimodalContent(text: msg.text, imageDatas: msg.imageDatas)
            } else {
                content = msg.text
            }
            return AIMessagePayload(role: msg.role, content: content)
        }
    }

    private func buildMultimodalContent(text: String, imageDatas: [Data]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        for data in imageDatas.prefix(SupportImageEncoder.maxImages) {
            guard let b64 = SupportImageEncoder.jpegBase64(from: data) else { continue }
            blocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": b64,
                ],
            ])
        }
        if !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        if blocks.isEmpty {
            blocks.append(["type": "text", "text": text.isEmpty ? "(immagine)" : text])
        }
        return blocks
    }

    private func encodeImagesForTicket() -> [String] {
        var seen = Set<Data>()
        var out: [String] = []
        for msg in messages {
            for data in msg.imageDatas {
                guard !seen.contains(data), let b64 = SupportImageEncoder.jpegBase64(from: data) else { continue }
                seen.insert(data)
                out.append(b64)
                if out.count >= SupportImageEncoder.maxImages { return out }
            }
        }
        for item in attachedImages {
            guard !seen.contains(item.data), let b64 = SupportImageEncoder.jpegBase64(from: item.data) else { continue }
            seen.insert(item.data)
            out.append(b64)
            if out.count >= SupportImageEncoder.maxImages { return out }
        }
        return out
    }
}
