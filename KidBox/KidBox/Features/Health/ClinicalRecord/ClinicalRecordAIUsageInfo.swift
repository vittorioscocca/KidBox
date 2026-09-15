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
    /// Sul Free il contatore è il bonus a vita, non si azzera: «oggi» sarebbe falso.
    let period: AIQuotaPeriod
    let isLargeContext: Bool
    let totalPayloadChars: Int

    init(
        messageUnitsConsumed: Int,
        usageToday: Int,
        dailyLimit: Int,
        period: AIQuotaPeriod = .daily,
        isLargeContext: Bool,
        totalPayloadChars: Int
    ) {
        self.messageUnitsConsumed = messageUnitsConsumed
        self.usageToday = usageToday
        self.dailyLimit = dailyLimit
        self.period = period
        self.isLargeContext = isLargeContext
        self.totalPayloadChars = totalPayloadChars
    }

    var usageSummary: String {
        // La chiave giornaliera è la stessa di Piano Alimentare e Fitness.
        let format = period == .lifetime
            ? NSLocalizedString(
                "%1$d messaggi AI · %2$d/%3$d del bonus gratuito",
                comment: "Clinical record AI usage summary on the Free lifetime bonus"
            )
            : NSLocalizedString(
                "%1$d messaggi AI · %2$d/%3$d oggi",
                comment: "Clinical record AI usage summary"
            )
        return String(format: format, messageUnitsConsumed, usageToday, dailyLimit)
    }

    var largeContextNotice: String? {
        guard isLargeContext else { return nil }
        return String(
            format: NSLocalizedString(
                "Contesto sanitario ampio: questa sintesi ha conteggiato %1$d messaggi AI.",
                comment: "Clinical record large-context notice"
            ),
            messageUnitsConsumed
        )
    }
}

enum ClinicalRecordAIError: LocalizedError {
    case quotaWouldExceed(needed: Int, remaining: Int, dailyLimit: Int, period: AIQuotaPeriod)
    case payloadTooLarge(chars: Int, maxChars: Int)

    var errorDescription: String? {
        switch self {
        case .quotaWouldExceed(let needed, let remaining, let dailyLimit, let period):
            // Sul Free non c'è un «domani»: il bonus non si rinnova.
            let format = period == .lifetime
                ? NSLocalizedString(
                    "Servono %1$d messaggi AI per questo aggiornamento ma del bonus gratuito ne restano %2$d su %3$d. Riduci i referti allegati o passa a Pro.",
                    comment: "Clinical record quota error on the Free lifetime bonus"
                )
                : NSLocalizedString(
                    "Servono %1$d messaggi AI per questo aggiornamento ma ne restano %2$d su %3$d oggi. Riprova domani o riduci i referti allegati.",
                    comment: "Clinical record quota error"
                )
            return String(format: format, needed, remaining, dailyLimit)
        case .payloadTooLarge(let chars, let maxChars):
            // Stessa chiave di Piano Alimentare e Fitness.
            return String(
                format: NSLocalizedString(
                    "Contesto troppo grande (%1$@ caratteri, max %2$@). Riduci i documenti allegati in Salute.",
                    comment: "Clinical record payload error"
                ),
                chars.formatted(), maxChars.formatted()
            )
        }
    }
}
