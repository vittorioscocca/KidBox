//
//  FitnessPlanModels.swift
//  KidBox
//
//  Modelli del Piano Fitness AI: input dell'onboarding, piano mensile
//  strutturato (4 settimane) e stato di completamento delle sessioni.
//
//  A differenza del Piano Alimentare — che è un testo generato una volta e
//  letto — il piano fitness è un calendario vivo: le sessioni cambiano stato
//  (fatta, saltata, spostata) e vengono riconciliate con gli allenamenti letti
//  da Apple Salute. Per questo l'AI restituisce JSON, non prosa.
//

import Foundation
import SwiftUI

// MARK: - Obiettivo

/// Obiettivo principale scelto nel wizard.
enum FitnessGoal: String, CaseIterable, Codable, Identifiable {
    case weightLoss
    case toning
    case race

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .weightLoss: return "Perdere peso"
        case .toning:     return "Tonificazione e salute"
        case .race:       return "Preparazione a una gara"
        }
    }

    var systemImage: String {
        switch self {
        case .weightLoss: return "flame"
        case .toning:     return "figure.strengthtraining.traditional"
        case .race:       return "flag.checkered"
        }
    }

    /// Testo inviato all'AI (il prompt è costruito in italiano, come gli altri builder Salute).
    var promptLabel: String {
        switch self {
        case .weightLoss: return "perdere peso preservando la massa muscolare"
        case .toning:     return "tonificazione generale e salute, senza obiettivi di peso"
        case .race:       return "preparazione a una gara o a un evento sportivo"
        }
    }
}

/// Disciplina sportiva: serve sia come attività da mettere nel piano (per
/// qualsiasi obiettivo, anche solo tonicità e salute) sia come gara di
/// riferimento quando l'obiettivo è `race`.
enum FitnessSport: String, CaseIterable, Codable, Identifiable {
    case running
    case walking
    case marathon
    case trail
    case cycling
    case swimming
    case triathlon
    case gym
    case bodyweight
    case functional
    case yoga
    case tennis
    case football
    case volleyball
    case basketball
    case martialArts
    case dance
    case climbing
    case rowing
    case skiing
    case other

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .running:     return "Corsa"
        case .walking:     return "Camminata / trekking"
        case .marathon:    return "Maratona / mezza"
        case .trail:       return "Trail / corsa in montagna"
        case .cycling:     return "Bici"
        case .swimming:    return "Nuoto"
        case .triathlon:   return "Triathlon"
        case .gym:         return "Palestra / pesi"
        case .bodyweight:  return "Corpo libero"
        case .functional:  return "Funzionale / HIIT"
        case .yoga:        return "Yoga / pilates"
        case .tennis:      return "Tennis / padel"
        case .football:    return "Calcio"
        case .volleyball:  return "Volley"
        case .basketball:  return "Basket"
        case .martialArts: return "Arti marziali / boxe"
        case .dance:       return "Danza / ballo"
        case .climbing:    return "Arrampicata"
        case .rowing:      return "Canottaggio / vogatore"
        case .skiing:      return "Sci / sport invernali"
        case .other:       return "Altro"
        }
    }

    /// Come attività da inserire nelle sedute.
    var promptLabel: String {
        switch self {
        case .running:     return "corsa"
        case .walking:     return "camminata veloce o trekking"
        case .marathon:    return "corsa di lunga distanza"
        case .trail:       return "trail o corsa in montagna"
        case .cycling:     return "bicicletta"
        case .swimming:    return "nuoto"
        case .triathlon:   return "triathlon (nuoto, bici, corsa)"
        case .gym:         return "palestra con pesi e macchine"
        case .bodyweight:  return "allenamento a corpo libero"
        case .functional:  return "allenamento funzionale o HIIT"
        case .yoga:        return "yoga o pilates"
        case .tennis:      return "tennis o padel"
        case .football:    return "calcio"
        case .volleyball:  return "pallavolo"
        case .basketball:  return "pallacanestro"
        case .martialArts: return "arti marziali o boxe"
        case .dance:       return "danza o ballo"
        case .climbing:    return "arrampicata"
        case .rowing:      return "canottaggio o vogatore"
        case .skiing:      return "sci o sport invernali"
        case .other:       return "altra attività indicata dall'utente"
        }
    }

    /// Come gara o evento di riferimento.
    var racePromptLabel: String {
        switch self {
        case .running:     return "gara di corsa su 5-10 km"
        case .walking:     return "marcia o trekking di lunga distanza"
        case .marathon:    return "maratona o mezza maratona"
        case .trail:       return "trail o corsa in montagna"
        case .cycling:     return "granfondo o gara di ciclismo"
        case .swimming:    return "gara di nuoto"
        case .triathlon:   return "triathlon"
        case .gym:         return "gara di sollevamento pesi"
        case .bodyweight:  return "gara di calisthenics"
        case .functional:  return "gara di cross training"
        case .yoga:        return "evento o stage intensivo"
        case .tennis:      return "torneo di tennis o padel"
        case .football:    return "campionato o torneo di calcio"
        case .volleyball:  return "campionato o torneo di volley"
        case .basketball:  return "campionato o torneo di basket"
        case .martialArts: return "incontro di arti marziali o boxe"
        case .dance:       return "gara o saggio di danza"
        case .climbing:    return "gara di arrampicata"
        case .rowing:      return "gara di canottaggio"
        case .skiing:      return "gara di sci o sport invernali"
        case .other:       return "evento sportivo"
        }
    }

    /// Discipline proponibili come gara: yoga e camminata restano fra gli sport
    /// praticabili, ma non hanno senso come evento di riferimento.
    static var raceOptions: [FitnessSport] {
        allCases.filter { $0 != .yoga && $0 != .walking }
    }
}

/// Esperienza dichiarata: determina volume e progressione del piano.
enum FitnessExperience: String, CaseIterable, Codable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .beginner:     return "Principiante"
        case .intermediate: return "Intermedio"
        case .advanced:     return "Avanzato"
        }
    }

    var promptLabel: String {
        switch self {
        case .beginner:     return "principiante (riparte da zero o si allena da meno di 3 mesi)"
        case .intermediate: return "intermedio (si allena con continuità da almeno 6 mesi)"
        case .advanced:     return "avanzato (allenamento strutturato da anni)"
        }
    }
}

/// Dove ci si allena: cambia completamente gli esercizi proposti.
enum FitnessPlace: String, CaseIterable, Codable, Identifiable {
    case home
    case gym
    case outdoor

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .home:    return "A casa"
        case .gym:     return "In palestra"
        case .outdoor: return "All'aperto"
        }
    }

    var promptLabel: String {
        switch self {
        case .home:    return "a casa, senza attrezzatura o con manubri leggeri ed elastici"
        case .gym:     return "in palestra, con accesso a bilancieri, macchine e cardio"
        case .outdoor: return "all'aperto, corsa e corpo libero"
        }
    }
}

// MARK: - Input del wizard

/// Parametri raccolti nell'onboarding, prima di invocare l'AI.
///
/// Età, peso e altezza sono chiesti solo quando l'app Salute non li fornisce,
/// come nel Piano Alimentare.
struct FitnessPlanInput: Codable, Equatable {
    var goal: FitnessGoal = .toning
    /// Sport che la persona vuole praticare, per QUALSIASI obiettivo: sono le
    /// attività attorno a cui l'AI costruisce le sedute, non solo un dettaglio
    /// della preparazione a una gara.
    var preferredSports: Set<FitnessSport> = []
    var raceType: FitnessSport?
    /// Descrizione libera della gara: usata quando `raceType == .other`, oppure
    /// per precisare distanza e livello ("mezza maratona sotto le 2 ore").
    var raceDetail: String = ""
    var raceDate: Date?

    /// Giorni disponibili, in convenzione `Calendar` (1 = domenica … 7 = sabato).
    var trainingWeekdays: Set<Int> = [2, 4, 6]
    /// Orario del promemoria, come minuti dalla mezzanotte.
    var reminderMinutesFromMidnight: Int = 18 * 60
    var reminderEnabled: Bool = true
    var sessionMinutes: Int = 45
    var experience: FitnessExperience = .beginner
    var place: FitnessPlace = .home
    var notes: String = ""

    var manualAgeYears: String = ""
    var manualWeightKg: String = ""
    var manualHeightCm: String = ""

    init() {}

    /// Decodifica tollerante: i piani salvati con versioni precedenti possono
    /// non avere tutti i campi.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(FitnessGoal.self, forKey: .goal) ?? .toning
        preferredSports = try c.decodeIfPresent(Set<FitnessSport>.self, forKey: .preferredSports) ?? []
        raceType = try c.decodeIfPresent(FitnessSport.self, forKey: .raceType)
        raceDetail = try c.decodeIfPresent(String.self, forKey: .raceDetail) ?? ""
        raceDate = try c.decodeIfPresent(Date.self, forKey: .raceDate)
        trainingWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .trainingWeekdays) ?? [2, 4, 6]
        reminderMinutesFromMidnight =
            try c.decodeIfPresent(Int.self, forKey: .reminderMinutesFromMidnight) ?? 18 * 60
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? true
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? 45
        experience = try c.decodeIfPresent(FitnessExperience.self, forKey: .experience) ?? .beginner
        place = try c.decodeIfPresent(FitnessPlace.self, forKey: .place) ?? .home
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        manualAgeYears = try c.decodeIfPresent(String.self, forKey: .manualAgeYears) ?? ""
        manualWeightKg = try c.decodeIfPresent(String.self, forKey: .manualWeightKg) ?? ""
        manualHeightCm = try c.decodeIfPresent(String.self, forKey: .manualHeightCm) ?? ""
    }

    /// Numero inserito a mano, accettando sia la virgola sia il punto decimale.
    private static func number(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    var manualAgeValue: Int? {
        Self.number(manualAgeYears).map { Int($0) }.flatMap { $0 > 0 && $0 < 120 ? $0 : nil }
    }
    var manualWeightValue: Double? {
        Self.number(manualWeightKg).flatMap { $0 >= 2 && $0 <= 400 ? $0 : nil }
    }
    var manualHeightValue: Double? {
        Self.number(manualHeightCm).flatMap { $0 >= 40 && $0 <= 260 ? $0 : nil }
    }

    /// Ora del promemoria come componenti calendario.
    var reminderHour: Int { reminderMinutesFromMidnight / 60 }
    var reminderMinute: Int { reminderMinutesFromMidnight % 60 }

    /// Sport preferiti nell'ordine dell'enum: il prompt deve essere stabile fra
    /// due generazioni identiche, e `Set` non lo è.
    var sortedSports: [FitnessSport] {
        FitnessSport.allCases.filter { preferredSports.contains($0) }
    }

    var sortedWeekdays: [Int] {
        // Ordinati partendo dal primo giorno della settimana locale (lunedì in IT).
        let first = Calendar.current.firstWeekday
        return trainingWeekdays.sorted { lhs, rhs in
            ((lhs - first + 7) % 7) < ((rhs - first + 7) % 7)
        }
    }

    /// Il wizard è completo? Serve almeno un giorno, e la gara va qualificata.
    var isComplete: Bool {
        guard !trainingWeekdays.isEmpty else { return false }
        if goal == .race {
            guard let raceType else { return false }
            if raceType == .other,
               raceDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }
}

// MARK: - Stato di una sessione

enum FitnessSessionStatus: String, Codable {
    case planned
    case done
    case skipped
    /// Spostata a un'altra data dalla notifica o dal copilota.
    case moved

    var label: LocalizedStringKey {
        switch self {
        case .planned: return "Da fare"
        case .done:    return "Completato"
        case .skipped: return "Saltato"
        case .moved:   return "Spostato"
        }
    }

    var systemImage: String {
        switch self {
        case .planned: return "circle"
        case .done:    return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .moved:   return "arrow.uturn.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .planned: return .secondary
        case .done:    return Color(red: 0.30, green: 0.72, blue: 0.45)
        case .skipped: return Color(red: 0.90, green: 0.42, blue: 0.35)
        case .moved:   return Color(red: 0.95, green: 0.68, blue: 0.25)
        }
    }
}

/// Come una sessione è stata segnata completata: serve al report settimanale
/// per distinguere l'autodichiarazione dal dato letto dall'orologio.
enum FitnessCompletionSource: String, Codable {
    case manual
    case notification
    case healthKit
}

// MARK: - Piano

struct FitnessExercise: Codable, Equatable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// "3 serie × 12 ripetizioni", "20 minuti a ritmo facile", …
    var detail: String
    var notes: String?

    init(id: String = UUID().uuidString, name: String, detail: String, notes: String? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.notes = notes
    }
}

/// Una singola giornata di allenamento del piano.
struct FitnessSession: Codable, Equatable, Identifiable {
    var id: String
    /// Data prevista (mezzanotte locale). Cambia quando la sessione viene spostata.
    var date: Date
    /// Data originale, conservata quando la sessione viene spostata.
    var originalDate: Date?
    var weekIndex: Int
    var title: String
    /// Categoria libera prodotta dall'AI ("corsa", "forza", "mobilità", …):
    /// usata solo per scegliere icona e per il match con gli allenamenti Salute.
    var activityType: String
    var durationMinutes: Int
    var intensity: String
    var exercises: [FitnessExercise]
    /// Obiettivi misurabili della giornata (minuti, kcal, serie/ripetizioni).
    var targets: [String]
    var targetKcal: Int?
    var notes: String?

    var status: FitnessSessionStatus = .planned
    var completedAt: Date?
    var completionSource: FitnessCompletionSource?
    /// UUID dell'allenamento Apple Salute che ha chiuso la sessione (anti doppio conteggio).
    var matchedWorkoutId: String?
    var actualMinutes: Int?
    var actualKcal: Int?

    init(
        id: String = UUID().uuidString,
        date: Date,
        originalDate: Date? = nil,
        weekIndex: Int,
        title: String,
        activityType: String,
        durationMinutes: Int,
        intensity: String,
        exercises: [FitnessExercise] = [],
        targets: [String] = [],
        targetKcal: Int? = nil,
        notes: String? = nil,
        status: FitnessSessionStatus = .planned,
        completedAt: Date? = nil,
        completionSource: FitnessCompletionSource? = nil,
        matchedWorkoutId: String? = nil,
        actualMinutes: Int? = nil,
        actualKcal: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.originalDate = originalDate
        self.weekIndex = weekIndex
        self.title = title
        self.activityType = activityType
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.exercises = exercises
        self.targets = targets
        self.targetKcal = targetKcal
        self.notes = notes
        self.status = status
        self.completedAt = completedAt
        self.completionSource = completionSource
        self.matchedWorkoutId = matchedWorkoutId
        self.actualMinutes = actualMinutes
        self.actualKcal = actualKcal
    }

    var isRest: Bool {
        let type = activityType.lowercased()
        return type.contains("ripos") || type.contains("rest") || type.contains("recupero")
    }

    /// Icona SF Symbols dedotta dal tipo di attività.
    var systemImage: String {
        let type = (activityType + " " + title).lowercased()
        let map: [(keys: [String], symbol: String)] = [
            (["cors", "run", "jog"], "figure.run"),
            (["camm", "walk", "passeg"], "figure.walk"),
            (["forza", "pesi", "strength", "tonific"], "figure.strengthtraining.traditional"),
            (["corpo libero", "calisten", "hiit", "circuit"], "figure.highintensity.intervaltraining"),
            (["bici", "cicl", "cycl", "spinning"], "figure.outdoor.cycle"),
            (["nuot", "swim", "piscina"], "figure.pool.swim"),
            (["mobil", "stretch", "yoga", "pilates"], "figure.flexibility"),
            (["ripos", "rest", "recupero"], "moon.zzz"),
        ]
        for entry in map where entry.keys.contains(where: { type.contains($0) }) {
            return entry.symbol
        }
        return "figure.mixed.cardio"
    }
}

/// Una settimana del piano mensile.
struct FitnessWeek: Codable, Equatable, Identifiable {
    var index: Int
    var focus: String
    var sessions: [FitnessSession]

    var id: Int { index }
}

/// Piano mensile generato dall'AI.
struct FitnessPlanDocument: Codable, Equatable {
    var subjectName: String
    var input: FitnessPlanInput
    /// Lunedì della prima settimana.
    var startDate: Date
    var summary: String
    /// Adattamenti dovuti a referti, patologie o terapie: mostrati in evidenza.
    var safetyNotes: [String]
    var weeks: [FitnessWeek]
    var generatedAt: Date
    var messageUnitsConsumed: Int

    var allSessions: [FitnessSession] {
        weeks.flatMap(\.sessions).sorted { $0.date < $1.date }
    }

    func session(id: String) -> FitnessSession? {
        weeks.lazy.flatMap(\.sessions).first { $0.id == id }
    }

    /// Aggiorna una sessione ovunque si trovi nel piano.
    mutating func updateSession(id: String, _ transform: (inout FitnessSession) -> Void) {
        for weekIndex in weeks.indices {
            guard let sessionIndex = weeks[weekIndex].sessions.firstIndex(where: { $0.id == id })
            else { continue }
            transform(&weeks[weekIndex].sessions[sessionIndex])
            return
        }
    }

    /// Sessioni di una giornata specifica.
    func sessions(on day: Date) -> [FitnessSession] {
        let cal = Calendar.current
        return allSessions.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    /// Settimana che contiene la data indicata (1-based), `nil` se fuori piano.
    func weekIndex(for day: Date) -> Int? {
        let cal = Calendar.current
        guard let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate),
                                            to: cal.startOfDay(for: day)).day,
              days >= 0
        else { return nil }
        let index = days / 7 + 1
        return weeks.contains(where: { $0.index == index }) ? index : nil
    }
}

// MARK: - Report settimanale

/// Sintesi di fine settimana mostrata all'utente (sezione 6 delle specifiche).
struct FitnessWeeklyReport: Codable, Equatable {
    var weekIndex: Int
    var weekStart: Date
    var plannedSessions: Int
    var completedSessions: Int
    var skippedSessions: Int
    var totalMinutes: Int
    var totalKcal: Int
    /// Giorni della settimana (convenzione `Calendar`) sistematicamente saltati.
    var chronicallySkippedWeekdays: [Int]

    var completionRate: Double {
        guard plannedSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(plannedSessions)
    }

    var completionPercent: Int { Int((completionRate * 100).rounded()) }

    /// Messaggio motivazionale, scelto localmente: non costa messaggi AI.
    var headline: String {
        let percent = completionPercent
        switch percent {
        case 100:
            return String(
                format: NSLocalizedString(
                    "Hai completato il 100%% del piano: settimana perfetta.",
                    comment: "Fitness weekly report headline perfect"
                )
            )
        case 70...99:
            return String(
                format: NSLocalizedString(
                    "Hai completato il %d%% del piano, ottima progressione.",
                    comment: "Fitness weekly report headline good"
                ),
                percent
            )
        case 40..<70:
            return String(
                format: NSLocalizedString(
                    "Hai completato il %d%% del piano: si può recuperare la prossima settimana.",
                    comment: "Fitness weekly report headline mid"
                ),
                percent
            )
        default:
            return String(
                format: NSLocalizedString(
                    "Hai completato il %d%% del piano: forse è troppo carico rispetto ai tuoi impegni.",
                    comment: "Fitness weekly report headline low"
                ),
                percent
            )
        }
    }
}

/// Proposta di adeguamento generata dall'AI a fine settimana.
struct FitnessAdjustmentProposal: Codable, Equatable {
    var rationale: String
    var changes: [String]
    /// Sessioni riscritte da applicare (stessi id di quelle esistenti, oppure nuove).
    var updatedSessions: [FitnessSession]
    var generatedAt: Date
    var weekIndex: Int
}

// MARK: - Contatori AI

/// Contatore messaggi AI dopo una generazione (allineato a askAI / AIAskAIPayload).
struct FitnessPlanAIUsageInfo: Equatable {
    let messageUnitsConsumed: Int
    let usageToday: Int
    let dailyLimit: Int
    let totalPayloadChars: Int

    var usageSummary: String {
        String(
            format: NSLocalizedString(
                "%1$d messaggi AI · %2$d/%3$d oggi",
                comment: "Fitness plan AI usage summary"
            ),
            messageUnitsConsumed, usageToday, dailyLimit
        )
    }
}

// MARK: - Errori

enum FitnessPlanAIError: LocalizedError {
    case planNotIncluded
    case quotaWouldExceed(needed: Int, remaining: Int, dailyLimit: Int)
    case payloadTooLarge(chars: Int, maxChars: Int)
    case missingHealthData
    case incompleteSetup
    case invalidPlanFormat
    case timedOut

    var errorDescription: String? {
        switch self {
        case .planNotIncluded:
            return NSLocalizedString(
                "Il Piano Fitness è incluso nei piani Pro e Max. Passa a Pro per generarlo.",
                comment: "Fitness plan paid-plan error"
            )
        case .quotaWouldExceed(let needed, let remaining, let dailyLimit):
            return String(
                format: NSLocalizedString(
                    "Servono %1$d messaggi AI per generare il piano ma ne restano %2$d su %3$d oggi. Riprova domani.",
                    comment: "Fitness plan quota error"
                ),
                needed, remaining, dailyLimit
            )
        case .payloadTooLarge(let chars, let maxChars):
            return String(
                format: NSLocalizedString(
                    "Contesto troppo grande (%1$@ caratteri, max %2$@). Riduci i documenti allegati in Salute.",
                    comment: "Fitness plan payload error"
                ),
                chars.formatted(), maxChars.formatted()
            )
        case .missingHealthData:
            return NSLocalizedString(
                "Servono almeno peso e altezza per creare il piano. Aggiornali nell'app Salute o nella Scheda Medica.",
                comment: "Fitness plan missing data error"
            )
        case .incompleteSetup:
            return NSLocalizedString(
                "Completa la configurazione: scegli l'obiettivo e almeno un giorno di allenamento.",
                comment: "Fitness plan incomplete setup error"
            )
        case .invalidPlanFormat:
            return NSLocalizedString(
                "L'AI ha risposto in un formato non riconosciuto. Riprova: di solito al secondo tentativo va a buon fine.",
                comment: "Fitness plan parse error"
            )
        case .timedOut:
            return NSLocalizedString(
                "La creazione del piano ha superato il tempo massimo. Riprova, di solito al secondo tentativo va a buon fine.",
                comment: "Fitness plan timeout error"
            )
        }
    }
}
