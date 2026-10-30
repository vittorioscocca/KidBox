//
//  WorkDocumentService.swift
//  KidBox
//
//  Legge una busta paga o un contratto (vision) e ne estrae i valori per la
//  scheda Lavoro. Purpose `workDoc`: solo Pro e Max, bloccato anche dal server.
//  Costo: 1 messaggio AI per pagina letta, al massimo 3 pagine.
//

import Foundation

enum WorkDocumentService {

    struct Result {
        /// `WorkRecordKind.payslip` | `.contract`
        let kind: String
        let fields: WorkFields
        let referenceDate: Date
    }

    enum AnalyzeError: Error {
        case unreadable
        case notAWorkDocument
        case badResponse
    }

    private static let purpose = "workDoc"

    static func analyze(data: Data, fileName: String, mimeType: String) async throws -> Result {
        let images = DocumentIntelligenceService.renderImages(data: data, mimeType: mimeType)
        guard !images.isEmpty else { throw AnalyzeError.unreadable }

        var blocks: [[String: Any]] = images.map { jpeg in
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
        }
        blocks.append(["type": "text",
                       "text": "File: \(fileName). Leggi il documento e rispondi con il JSON richiesto."])

        let response = try await AIService.shared.sendMessages(
            messages: [AIMessagePayload(role: "user", content: blocks)],
            systemPrompt: systemPrompt,
            purpose: purpose
        )
        return try parse(response.reply)
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    Sei l'assistente di KidBox. Leggi un documento di lavoro (immagini delle pagine) e ne estrai i \
    valori. Rispondi ESCLUSIVAMENTE con un oggetto JSON valido (nessun testo prima o dopo, niente \
    markdown, niente ```), con questa forma:
    {
      "kind": "payslip|contract|leavePlan|other",
      "referenceDate": "yyyy-MM-dd",
      "fields": {
        "title": "titolo breve, es. Busta paga settembre 2026 / Contratto a tempo indeterminato",
        "employer": "datore di lavoro",
        "period": "mese di competenza della busta paga, es. Settembre 2026",
        "gross": 0, "net": 0, "taxes": 0, "contributions": 0,
        "vacationAccrued": 0, "vacationTaken": 0, "vacationRemaining": 0,
        "permitHoursAccrued": 0, "permitHoursRemaining": 0, "tfr": 0,
        "contractType": "tempo indeterminato|tempo determinato|apprendistato|partita IVA|altro",
        "startDate": "yyyy-MM-dd", "endDate": "yyyy-MM-dd",
        "grossAnnual": 0, "level": "livello e/o CCNL", "noticePeriod": "preavviso",
        "vacationDaysPerYear": 0, "notes": "altro di rilevante",
        "leavePeriods": [{"start": "yyyy-MM-dd", "end": "yyyy-MM-dd", "label": "Ferie|Permesso|ROL|Malattia|altro"}]
      }
    }

    REGOLE:
    - "payslip" = busta paga / cedolino; "contract" = contratto di lavoro o lettera di assunzione/proroga; \
      "leavePlan" = foglio, piano o calendario delle ferie e dei permessi con date precise; altro documento → "other" con "fields": {}.
    - NON INVENTARE. Se un valore non c'è nel documento OMETTI il campo: niente zeri di ripiego.
    - Importi come numeri con il punto decimale, in euro, senza simbolo. "gross" = totale competenze lorde \
      del mese; "net" = netto in busta; "taxes" = IRPEF e addizionali trattenute nel mese; "contributions" = \
      contributi previdenziali a carico del lavoratore (INPS).
    - Ferie in GIORNI (o in ORE se così è scritto: in tal caso convertile solo se il documento dice quante \
      ore valgono un giorno, altrimenti riporta il numero e scrivilo in "notes"). "vacationRemaining" è il \
      saldo residuo, "vacationAccrued" quanto maturato nel periodo o nell'anno, "vacationTaken" il goduto.
    - Permessi (ROL, ex festività) in ORE: "permitHoursRemaining" è il saldo residuo.
    - "referenceDate": per la busta paga il primo giorno del mese di competenza; per il contratto la data \
      di inizio. Date in formato yyyy-MM-dd.
    - "leavePlan": in "leavePeriods" metti SOLO i giorni di assenza segnati nel documento, uno per periodo; \
      raggruppa i giorni consecutivi in un solo periodo (start = primo giorno, end = ultimo), un giorno solo ha \
      start = end. Non aggiungere giorni non segnati, non includere festivi o weekend che non sono indicati. \
      Se manca l'anno, usa quello più probabile dal contesto del documento. "label" è il tipo di assenza come \
      scritto (ferie, permesso, ROL). "referenceDate" è l'inizio del primo periodo; "title" es. «Ferie 2026».
    - Non dare giudizi né consigli: estrai solo ciò che è scritto.
    """

    // MARK: - Parse

    private static func parse(_ reply: String) throws -> Result {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let nl = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: nl)...])
            if let fence = text.range(of: "```", options: .backwards) { text = String(text[..<fence.lowerBound]) }
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8)
        else { throw AnalyzeError.badResponse }

        struct Raw: Decodable {
            let kind: String?
            let referenceDate: String?
            let fields: WorkFields?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { throw AnalyzeError.badResponse }
        guard let kind = raw.kind,
              [WorkRecordKind.payslip, WorkRecordKind.contract, WorkRecordKind.leavePlan].contains(kind),
              var fields = raw.fields
        else { throw AnalyzeError.notAWorkDocument }
        if kind == WorkRecordKind.leavePlan {
            fields.leavePeriods = fields.leavePeriods
                .filter { $0.startDay != nil }
                .sorted { ($0.startDay ?? .distantPast) < ($1.startDay ?? .distantPast) }
            // In bozza ogni periodo parte con «Aggiungi al calendario» acceso: lo spegne chi non lo vuole.
            for i in fields.leavePeriods.indices { fields.leavePeriods[i].inCalendar = true }
            guard !fields.leavePeriods.isEmpty else { throw AnalyzeError.notAWorkDocument }
        }
        let ref = WorkFields.parseDay(raw.referenceDate)
            ?? fields.leavePeriods.first?.startDay
            ?? WorkFields.parseDay(fields.startDate)
            ?? Date()
        return Result(kind: kind, fields: fields, referenceDate: ref)
    }
}
