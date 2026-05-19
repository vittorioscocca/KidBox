//
//  AIAskAIPayload.swift
//  KidBox
//
//  Allineato a askAI in functions/index.js: oltre ~50k caratteri (system + cronologia)
//  ogni richiesta scala più messaggi sul contatore giornaliero famiglia.
//

import Foundation

enum AIAskAIPayload {

    /// Caratteri payload considerati equivalenti a 1 messaggio (parity server).
    static let standardChars = 50_000

    /// Limite assoluto lato server (anti-abuso).
    static let absoluteMaxChars = 500_000

    static func totalChars(systemPrompt: String, messages: [KBAIMessage], pendingUserText: String = "") -> Int {
        let history = messages.reduce(0) { $0 + $1.content.count }
        let pending = pendingUserText.trimmingCharacters(in: .whitespacesAndNewlines).count
        return systemPrompt.count + history + pending
    }

    static func messageUnits(totalChars: Int) -> Int {
        guard totalChars > 0 else { return 1 }
        return max(1, Int(ceil(Double(totalChars) / Double(standardChars))))
    }

    static func isLargeContext(totalChars: Int) -> Bool {
        messageUnits(totalChars: totalChars) > 1
    }

    /// Testo da mostrare sopra l'input quando il contesto supera lo standard.
    static func transientLargeContextNotice() -> String {
        "Contesto sanitario ampio: alla prossima domanda potrai scegliere tra risposta accurata o contesto riassunto."
    }

    static func choiceDialogMessage(
        fullUnits: Int,
        compactAskUnits: Int,
        compactSetupUnits: Int,
        hasCompactCache: Bool
    ) -> String {
        if hasCompactCache {
            return """
            Il profilo sanitario inviato all'AI supera lo standard (~\(standardChars.formatted()) caratteri). \
            Scegli come procedere per questa domanda: accurata (\(fullUnits) messaggi) o riassunta \
            (\(compactAskUnits) messaggio\(compactAskUnits == 1 ? "" : "i")).
            """
        }
        return """
        Il profilo sanitario è molto ampio. Accuratezza: \(fullUnits) messaggi per questa domanda. \
        Riassunto: \(compactAskUnits) messaggio\(compactAskUnits == 1 ? "" : "i") per questa domanda, \
        più \(compactSetupUnits) messaggio\(compactSetupUnits == 1 ? "" : "i") una sola volta in questa chat \
        per creare il riassunto (le domande successive con riassunto costano meno).
        """
    }

    static func compactChoiceButtonLabel(askUnits: Int, setupUnits: Int) -> String {
        if setupUnits > 0 {
            return "Contesto riassunto (\(askUnits) + \(setupUnits) una tantum)"
        }
        let suffix = askUnits == 1 ? "messaggio" : "messaggi"
        return "Contesto riassunto (\(askUnits) \(suffix))"
    }
}
