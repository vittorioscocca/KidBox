//
//  ClinicalRecordAIUsageInfo.swift
//  KidBox
//

import Foundation

/// Contatore messaggi AI dopo sintesi cartella clinica (allineato a askAI / AIAskAIPayload).
struct ClinicalRecordAIUsageInfo: Equatable {
    let messageUnitsConsumed: Int
    let usageToday: Int
    let dailyLimit: Int
    let isLargeContext: Bool
    let totalPayloadChars: Int

    var usageSummary: String {
        let unitLabel = messageUnitsConsumed == 1 ? "messaggio" : "messaggi"
        return "\(messageUnitsConsumed) \(unitLabel) AI · \(usageToday)/\(dailyLimit) oggi"
    }

    var largeContextNotice: String? {
        guard isLargeContext else { return nil }
        return "Contesto sanitario ampio: conteggio \(messageUnitsConsumed) messaggi sul limite giornaliero famiglia."
    }
}

enum ClinicalRecordAIError: LocalizedError {
    case quotaWouldExceed(needed: Int, remaining: Int, dailyLimit: Int)
    case payloadTooLarge(chars: Int, maxChars: Int)

    var errorDescription: String? {
        switch self {
        case .quotaWouldExceed(let needed, let remaining, let dailyLimit):
            return "Servono \(needed) messaggi AI per questo aggiornamento ma ne restano \(remaining) su \(dailyLimit) oggi. Riprova domani o riduci i referti allegati."
        case .payloadTooLarge(let chars, let maxChars):
            return "Contesto troppo grande (\(chars.formatted()) caratteri, max \(maxChars.formatted())). Riduci i documenti allegati in Salute."
        }
    }
}
