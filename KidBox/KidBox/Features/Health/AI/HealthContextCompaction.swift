//
//  HealthContextCompaction.swift
//  KidBox
//

import Foundation

enum HealthContextSendMode: String, CaseIterable, Identifiable {
    case fullAccuracy
    case compactSummary

    var id: String { rawValue }
}

/// Preferenza utente per la chat Salute (Impostazioni AI + scelta nel dialog).
enum HealthContextSendPreference: String, CaseIterable, Identifiable {
    case askEachTime
    case fullAccuracy
    case compactSummary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .askEachTime: return "Chiedi ogni volta"
        case .fullAccuracy: return "Massima accuratezza"
        case .compactSummary: return "Contesto riassunto"
        }
    }

    var detail: String {
        switch self {
        case .askEachTime:
            return "Con contesto ampio mostra la scelta prima di ogni invio."
        case .fullAccuracy:
            return "Invia sempre tutti i referti e i dati sanitari completi."
        case .compactSummary:
            return "Usa un riassunto del profilo sanitario per risparmiare messaggi."
        }
    }

    var sendMode: HealthContextSendMode? {
        switch self {
        case .askEachTime: return nil
        case .fullAccuracy: return .fullAccuracy
        case .compactSummary: return .compactSummary
        }
    }

    static func from(sendMode: HealthContextSendMode) -> HealthContextSendPreference {
        switch sendMode {
        case .fullAccuracy: return .fullAccuracy
        case .compactSummary: return .compactSummary
        }
    }

    /// Valore canonico su Firestore (`users/{uid}.aiPrefs`), allineato ad Android.
    var firestoreValue: String {
        switch self {
        case .askEachTime: return "ask_each_time"
        case .fullAccuracy: return "full_accuracy"
        case .compactSummary: return "compact_summary"
        }
    }

    static func fromFirestoreValue(_ value: String?) -> HealthContextSendPreference {
        guard let value, !value.isEmpty else { return .askEachTime }
        if let local = HealthContextSendPreference(rawValue: value) { return local }
        switch value {
        case "ask_each_time": return .askEachTime
        case "full_accuracy": return .fullAccuracy
        case "compact_summary": return .compactSummary
        default: return .askEachTime
        }
    }
}

enum HealthContextCompaction {

    static let summarizationSystemPrompt = """
    Sei un assistente che comprime dati sanitari per uso come contesto di un'altra AI.
    Riassumi fedelmente il testo seguente mantenendo:
    - cure attive e dosaggi
    - vaccini e date rilevanti
    - visite, diagnosi, raccomandazioni ed esami prescritti
    - risultati e valori chiave citati nei referti
    - scadenze urgenti o esami in attesa
    Non inventare dati. Usa elenchi chiari. Rispondi solo con il riassunto, in italiano.
    """

    static func buildCompactSystemPrompt(summary: String, subjectName: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Sei un assistente medico informativo integrato in KidBox, pensato per genitori.
        Stai assistendo \(subjectName). Il contesto sanitario completo è stato riassunto per limiti tecnici: \
        se manca un dettaglio, chiedi all'utente o indica il limite.
        Usa un linguaggio semplice. Ricorda di consultare il medico per pareri clinici vincolanti. Rispondi in italiano.

        --- CONTESTO SANITARIO (RIASSUNTO) ---
        \(trimmed)

        --- FINE RIASSUNTO ---
        \(PlanningAIActionBlock.promptSection)
        """
    }
}
