//
//  ClinicalRecordAISynthesizer.swift
//  KidBox
//

import Foundation

/// Sintesi cartella clinica via Cloud Function `askAI` (Anthropic Sonnet lato server).
enum ClinicalRecordAISynthesizer {

    private static let systemPrompt = """
    Sei un medico di famiglia che redige una cartella clinica sintetica e professionale.
    Scrivi esclusivamente in prosa narrativa fluente in italiano.

    REGOLE ASSOLUTE:
    ZERO bullet point, ZERO trattini elenco, ZERO elenchi puntati o numerati.
    ZERO intestazioni ripetitive tipo "Valore:", "Data:", "Risultato:".
    Ogni sezione è un paragrafo continuo di 3-6 frasi.
    I dati numerici (pressione, peso, altezza, esami di laboratorio, FC, ecc.) vanno INCORPORATI nel testo, mai elencati.
    Descrivi come i valori sono CAMBIATI NEL TEMPO: usa frasi come "si è mantenuta stabile",
    "ha mostrato una lieve riduzione da X a Y", "è progressivamente aumentato fino a",
    "dopo il picco di X nel mese Y, è tornato nella norma".
    Se hai un solo dato, descrivi il contesto: "L'unica misurazione disponibile, risalente a...".
    Non usare MAI valori che non sono presenti nei dati forniti.
    Se un dato è assente, scrivi "Non sono disponibili misurazioni per questo parametro".
    Le date in formato GG/MM o GG/MM/AAAA non sono valori di pressione: non usarle come sistolica/diastolica.
    Ogni lesione (angioma, cisti, nodulo) va descritta separatamente per tipo, sede anatomica e dimensione in mm.
    Il confronto temporale è valido solo con almeno due misurazioni della stessa entità e date certe.
    Se ti viene spontaneo usare un elenco, fermati e riformula come frase completa con "inoltre", "mentre", "al contrario", ecc.

    \(ClinicalRecordPromptRules.supplementalRules)

    STRUTTURA DEL DOCUMENTO (usa --- come separatore tra blocchi; titoli sezione in MAIUSCOLO su una riga sola):
    1) Prima riga: CARTELLA CLINICA — NOME COGNOME
    2) Righe anagrafiche in prosa breve (data di nascita, età, residenza, gruppo sanguigno se presenti)
    3) --- DATI APPLE HEALTH / WEARABLE (solo se presenti nei dati; disclaimer consumer + prosa su FC, VO2, attività, SpO2, passi, HRV)
    4) --- STATO ATTUALE DELLE CURE (paragrafo sulle terapie in corso, senza elenchi)
    5) --- per ogni area clinica rilevante (CARDIOLOGIA con anche pressione arteriosa, GASTROENTEROLOGIA, UROLOGIA, LABORATORIO…): \
    titolo in maiuscolo, poi un solo paragrafo narrativo con quadro, evoluzione temporale e conclusione.
    VIETATA sezione standalone «PRESSIONE ARTERIOSA».
    6) --- ESAMI IN ATTESA (se presenti)
    7) --- RIEPILOGO (massimo 6 frasi)

    Rispondi SOLO con il testo della cartella, senza commenti meta.
    Vietato Markdown: niente asterischi, cancelletti, backtick o simboli */ /*.
    """

    /// Stima caratteri e messaggi (parity server: system + user + regole cartella clinica).
    static func estimatePayload(
        nativeReport: ClinicalRecordReport,
        healthContext: String
    ) -> (totalChars: Int, messageUnits: Int, isLargeContext: Bool) {
        let userContent = buildUserContent(nativeReport: nativeReport, healthContext: healthContext)
        let base = AIAskAIPayload.totalChars(
            systemPrompt: systemPrompt,
            messages: [KBAIMessage(role: .user, content: userContent)]
        )
        let total = base + serverRulesOverheadChars
        // Cartella clinica: minimo fisso (Sonnet ~3× Haiku), parity server.
        let units = AIAskAIPayload.clinicalRecordMessageUnits(totalChars: total)
        return (total, units, AIAskAIPayload.isLargeContext(totalChars: total))
    }

    static func enhance(
        nativeReport: ClinicalRecordReport,
        healthContext: String
    ) async throws -> (report: ClinicalRecordReport, usage: ClinicalRecordAIUsageInfo?) {
        guard AISettings.shared.isEnabled else { return (nativeReport, nil) }
        guard KBSubscriptionManager.shared.currentPlan.includesAI else { return (nativeReport, nil) }

        let estimate = estimatePayload(nativeReport: nativeReport, healthContext: healthContext)
        if estimate.totalChars > AIAskAIPayload.absoluteMaxChars {
            throw ClinicalRecordAIError.payloadTooLarge(
                chars: estimate.totalChars,
                maxChars: AIAskAIPayload.absoluteMaxChars
            )
        }

        if let current = try? await AIService.shared.fetchUsage() {
            let remaining = max(0, current.dailyLimit - current.usageToday)
            if estimate.messageUnits > remaining {
                throw ClinicalRecordAIError.quotaWouldExceed(
                    needed: estimate.messageUnits,
                    remaining: remaining,
                    dailyLimit: current.dailyLimit
                )
            }
        }

        let userContent = buildUserContent(nativeReport: nativeReport, healthContext: healthContext)
        KBLog.ai.kbInfo(
            "ClinicalRecordAISynthesizer: request chars=\(estimate.totalChars) units=\(estimate.messageUnits) large=\(estimate.isLargeContext)"
        )

        let response = try await AIService.shared.sendMessage(
            messages: [KBAIMessage(role: .user, content: userContent)],
            systemPrompt: systemPrompt,
            purpose: "clinicalRecord"
        )

        var cleaned = ClinicalRecordTextSanitizer.sanitize(response.reply)
        cleaned = collapseStrayListLines(cleaned)
        let parsed = ClinicalRecordTextSanitizer.sanitizeReport(
            ClinicalRecordReportParser.parse(
                text: cleaned,
                subjectName: nativeReport.subjectName,
                source: .aiEnhanced
            )
        )

        let usage = ClinicalRecordAIUsageInfo(
            messageUnitsConsumed: response.messageUnitsConsumed,
            usageToday: response.usageToday,
            dailyLimit: response.dailyLimit,
            isLargeContext: response.isLargeContext,
            totalPayloadChars: response.totalPayloadChars ?? estimate.totalChars
        )
        KBLog.ai.kbInfo(
            "ClinicalRecordAISynthesizer: done lines=\(parsed.fullDocumentLines.count) usage=\(usage.usageSummary)"
        )
        return (parsed, usage)
    }

    /// Regole aggiunte lato server (`CLINICAL_RECORD_SYSTEM_RULES` in index.js).
    private static let serverRulesOverheadChars = 700

    private static func buildUserContent(
        nativeReport: ClinicalRecordReport,
        healthContext: String
    ) -> String {
        """
        Redigi la cartella clinica narrativa per \(nativeReport.subjectName).
        Integra la bozza nativa e i dati grezzi; sostituisci ogni elenco con prosa continua.

        BOZZA NATIVA (riferimento strutturato, da trasformare in narrativa):
        \(nativeReport.fullDocumentLines.joined(separator: "\n"))

        DATI GREZZI APP (fonte primaria per numeri e date):
        \(healthContext)
        """
    }

    /// Unisce righe residue da elenchi AI in paragrafi continui.
    private static func collapseStrayListLines(_ text: String) -> String {
        var blocks: [String] = []
        var current: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: " "))
                    current = []
                }
                continue
            }
            if line == "---" || isCapsSection(line) {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: " "))
                    current = []
                }
                blocks.append(line)
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { blocks.append(current.joined(separator: " ")) }
        return blocks.joined(separator: "\n\n")
    }

    private static func isCapsSection(_ line: String) -> Bool {
        line == line.uppercased() && line.count > 6 && !line.hasPrefix("CARTELLA CLINICA")
    }
}
