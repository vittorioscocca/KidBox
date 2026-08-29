//
//  MealPlanModels.swift
//  KidBox
//

import Foundation
import SwiftUI

/// Obiettivo del piano alimentare scelto dall'utente.
enum MealPlanGoal: String, CaseIterable, Codable, Identifiable {
    case fatLoss
    case maintenance
    case muscleGain

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .fatLoss:     return "Perdere grasso"
        case .maintenance: return "Mantenere"
        case .muscleGain:  return "Massa magra"
        }
    }

    /// Testo inviato all'AI (non localizzato: il prompt è costruito lato client in italiano).
    var promptLabel: String {
        switch self {
        case .fatLoss:     return "perdere grasso mantenendo la massa muscolare"
        case .maintenance: return "mantenere il peso migliorando la qualità della dieta"
        case .muscleGain:  return "aumentare la massa magra con un surplus calorico contenuto"
        }
    }
}

/// Livello di attività dichiarato, usato per stimare le calorie di mantenimento.
enum MealPlanActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary
    case light
    case moderate
    case intense

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .sedentary: return "Sedentario"
        case .light:     return "Leggero"
        case .moderate:  return "Moderato"
        case .intense:   return "Intenso"
        }
    }

    var promptLabel: String {
        switch self {
        case .sedentary: return "sedentario (poco o nessun allenamento)"
        case .light:     return "leggero (1-2 allenamenti a settimana)"
        case .moderate:  return "moderato (3-4 allenamenti a settimana)"
        case .intense:   return "intenso (5 o più allenamenti a settimana)"
        }
    }
}

/// Input raccolti nel form prima della generazione.
struct MealPlanInput: Codable, Equatable {
    var goal: MealPlanGoal = .fatLoss
    var activityLevel: MealPlanActivityLevel = .moderate
    var preferredFoods: String = ""
    var avoidedFoods: String = ""
    var notes: String = ""
}

/// Piano alimentare generato, salvato in locale per non doverlo rigenerare.
struct MealPlanDocument: Codable, Equatable {
    var subjectName: String
    var input: MealPlanInput
    var text: String
    var generatedAt: Date
    var messageUnitsConsumed: Int

    var sections: [MealPlanSection] { MealPlanSection.parse(text) }
}

/// Blocco di testo del piano, ricavato dai titoli in MAIUSCOLO prodotti dall'AI.
struct MealPlanSection: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String

    /// Divide il testo AI su titoli in MAIUSCOLO (una riga sola) o separatori `---`.
    static func parse(_ text: String) -> [MealPlanSection] {
        var sections: [MealPlanSection] = []
        var currentTitle = ""
        var currentBody: [String] = []

        func flush() {
            let body = currentBody
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentTitle.isEmpty || !body.isEmpty else { return }
            sections.append(
                MealPlanSection(
                    id: "\(sections.count)-\(currentTitle)",
                    title: currentTitle,
                    body: body
                )
            )
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { continue }
            if isTitle(line) {
                flush()
                currentTitle = line
                currentBody = []
            } else {
                currentBody.append(raw)
            }
        }
        flush()
        return sections
    }

    private static func isTitle(_ line: String) -> Bool {
        guard line.count > 3, line.count <= 80 else { return false }
        guard line.rangeOfCharacter(from: .letters) != nil else { return false }
        return line == line.uppercased()
    }
}

/// Contatore messaggi AI dopo la generazione (allineato a askAI / AIAskAIPayload).
struct MealPlanAIUsageInfo: Equatable {
    let messageUnitsConsumed: Int
    let usageToday: Int
    let dailyLimit: Int
    let totalPayloadChars: Int

    var usageSummary: String {
        String(
            format: NSLocalizedString(
                "%1$d messaggi AI · %2$d/%3$d oggi",
                comment: "Meal plan AI usage summary"
            ),
            messageUnitsConsumed, usageToday, dailyLimit
        )
    }
}

enum MealPlanAIError: LocalizedError {
    case planNotIncluded
    case quotaWouldExceed(needed: Int, remaining: Int, dailyLimit: Int)
    case payloadTooLarge(chars: Int, maxChars: Int)
    case missingHealthData

    var errorDescription: String? {
        switch self {
        case .planNotIncluded:
            return NSLocalizedString(
                "Il Piano Alimentare è incluso nei piani Pro e Max. Passa a Pro per generarlo.",
                comment: "Meal plan paid-plan error"
            )
        case .quotaWouldExceed(let needed, let remaining, let dailyLimit):
            return String(
                format: NSLocalizedString(
                    "Servono %1$d messaggi AI per generare il piano ma ne restano %2$d su %3$d oggi. Riprova domani.",
                    comment: "Meal plan quota error"
                ),
                needed, remaining, dailyLimit
            )
        case .payloadTooLarge(let chars, let maxChars):
            return String(
                format: NSLocalizedString(
                    "Contesto troppo grande (%1$@ caratteri, max %2$@). Riduci i documenti allegati in Salute.",
                    comment: "Meal plan payload error"
                ),
                chars.formatted(), maxChars.formatted()
            )
        case .missingHealthData:
            return NSLocalizedString(
                "Servono almeno peso e altezza per creare il piano. Aggiornali nell'app Salute o nella Scheda Medica.",
                comment: "Meal plan missing data error"
            )
        }
    }
}
