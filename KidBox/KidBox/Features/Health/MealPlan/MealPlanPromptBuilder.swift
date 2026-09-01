//
//  MealPlanPromptBuilder.swift
//  KidBox
//
//  Costruisce system prompt e contenuto utente per la generazione AI del
//  piano alimentare. Il testo del prompt resta in italiano (come gli altri
//  builder Salute): la lingua della RISPOSTA è imposta esplicitamente.
//

import Foundation

enum MealPlanPromptBuilder {

    /// Referti allegati: tetto più basso della chat Salute — al piano alimentare
    /// serve il quadro clinico, non il referto integrale.
    static let refertoMaxChars = 1_200

    // MARK: - System prompt

    static func systemPrompt(responseLanguage: String) -> String {
        """
        Agisci come un coach di nutrizione e fitness basato sull'evidenza, integrato nell'app KidBox.
        Analizzi età, altezza, peso, livello di attività, allenamenti, alimentazione, visite mediche,
        cure in corso ed esami di laboratorio della persona per costruire un piano alimentare pratico.

        LINGUA DELLA RISPOSTA: \(responseLanguage). Scrivi TUTTO il piano in questa lingua.

        COSA DEVI PRODURRE, IN QUEST'ORDINE:
        1) STIMA CALORICA — stima le calorie di mantenimento a partire da età, altezza, peso, livello di
        attività e allenamenti registrati, poi definisci un deficit (o surplus) calorico realistico
        coerente con l'obiettivo. Usa INTERVALLI, non falsa precisione. Aggiungi una riga su come
        adattare le calorie alle variazioni settimanali del peso. Massimo 6 righe.
        2) OBIETTIVI DI MACRONUTRIENTI — proteine, carboidrati e grassi come intervalli giornalieri, più
        una riga sul perché di quella ripartizione. Massimo 5 righe.
        3) PIANO DEI PASTI — UNA sola giornata tipo (colazione, pranzo, cena, 1-2 spuntini) sul target
        calorico stimato, costruita con gli alimenti graditi. Per ogni pasto una riga con porzioni e
        calorie, e una riga con proteine/carboidrati/grassi. Per ogni pasto UNA sola alternativa
        equivalente, su una riga. Se ci sono allenamenti, aggiungi 2 righe su cosa mangiare prima e dopo.
        Massimo 30 righe in tutto.
        4) IDRATAZIONE — acqua e sali, adattati agli allenamenti. Massimo 4 righe.
        5) LISTA DELLA SPESA — solo gli alimenti della giornata tipo, raggruppati per reparto, una riga
        per reparto con gli alimenti separati da virgola. Massimo 8 righe.
        6) PIANO 90 GIORNI — tre blocchi (mese 1, mese 2, mese 3), massimo 3 righe ciascuno, con calorie,
        proteine, allenamento e obiettivo intermedio del mese.
        7) NOTE DI SALUTE — come condizioni cliniche, cure in corso, allergie e valori di laboratorio
        presenti nei dati influenzano il piano. Se un dato manca, dillo. Massimo 6 righe.

        LUNGHEZZA:
        L'INTERO piano deve stare in circa 1200 parole. È un vincolo, non un suggerimento: meglio una
        sezione asciutta che un piano tagliato a metà. Scrivi frasi brevi, niente introduzioni, niente
        riepiloghi di quanto hai appena scritto, niente ripetizioni delle regole tra una sezione e l'altra.
        Devi arrivare fino in fondo alla sezione 7: se stai correndo lungo, accorcia le sezioni successive.

        REGOLE ASSOLUTE:
        Il piano deve essere economico, saziante, bilanciato e realistico da seguire per 90 giorni.
        Dai priorità a un progresso sostenibile, al mantenimento della massa muscolare e alla salute generale.
        NON raccomandare diete estreme, restrizioni eccessive, digiuni prolungati o metodi pericolosi.
        NON inventare valori clinici assenti dai dati forniti.
        Rispetta sempre allergie, intolleranze e alimenti da evitare indicati.
        Se la persona ha meno di 18 anni, è in gravidanza o in allattamento, NON generare un piano
        ipocalorico: fornisci solo indicazioni educative sull'equilibrio dei pasti e rimanda al
        pediatra o allo specialista.
        Chiudi ricordando che il piano è educativo e va validato dal medico o dal nutrizionista curante.

        FORMATO:
        Titoli di sezione in MAIUSCOLO su una riga sola, esattamente nell'ordine sopra.
        Sotto ogni titolo usa testo semplice; per i pasti sono ammessi elenchi brevi con "-".
        Vietato Markdown: niente asterischi, cancelletti, backtick o tabelle.
        """
    }

    // MARK: - User content

    static func userContent(
        subjectName: String,
        input: MealPlanInput,
        profileSummary: [String],
        healthContext: String
    ) -> String {
        var lines: [String] = []
        lines.append("Crea il piano alimentare per \(subjectName).")
        lines.append("")
        lines.append("--- OBIETTIVO E PREFERENZE ---")
        lines.append("Obiettivo: \(input.goal.promptLabel)")
        lines.append("Livello di attività dichiarato: \(input.activityLevel.promptLabel)")

        let preferred = input.preferredFoods.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(
            preferred.isEmpty
                ? "Alimenti graditi: non indicati, usa alimenti comuni, economici e sazianti."
                : "Alimenti graditi: \(preferred)"
        )

        let avoided = input.avoidedFoods.trimmingCharacters(in: .whitespacesAndNewlines)
        if !avoided.isEmpty {
            lines.append("Alimenti da evitare / intolleranze: \(avoided)")
        }

        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("Note aggiuntive: \(notes)")
        }

        lines.append("")
        lines.append("--- DATI ANTROPOMETRICI E ALLENAMENTI (app Salute) ---")
        if profileSummary.isEmpty {
            lines.append("Nessun dato antropometrico disponibile.")
        } else {
            lines.append(contentsOf: profileSummary)
        }

        lines.append("")
        lines.append("--- DATI CLINICI (visite, cure, analisi, referti) ---")
        lines.append(healthContext)

        return lines.joined(separator: "\n")
    }

    // MARK: - Profilo antropometrico

    /// Righe compatte su età, altezza, peso e allenamenti recenti.
    static func profileSummaryLines(
        birthDate: Date?,
        snapshot: KBHealthImportSnapshot?,
        profile: KBPediatricProfile?,
        input: MealPlanInput = MealPlanInput()
    ) -> [String] {
        profileSummaryLines(
            birthDate: birthDate,
            snapshot: snapshot,
            profile: profile,
            manualAge: input.manualAgeValue,
            manualWeight: input.manualWeightValue,
            manualHeight: input.manualHeightValue
        )
    }

    /// Variante usata anche dal Piano Fitness, che ha un input suo: i valori
    /// inseriti a mano arrivano già normalizzati, senza passare da `MealPlanInput`.
    static func profileSummaryLines(
        birthDate: Date?,
        snapshot: KBHealthImportSnapshot?,
        profile: KBPediatricProfile?,
        manualAge: Int?,
        manualWeight: Double?,
        manualHeight: Double?
    ) -> [String] {
        var lines: [String] = []

        let effectiveBirthDate = birthDate ?? snapshot?.birthDate
        if let effectiveBirthDate {
            let years = Calendar.current.dateComponents([.year], from: effectiveBirthDate, to: Date()).year ?? 0
            lines.append("Età: \(years) anni")
        } else if let age = manualAge {
            lines.append("Età: \(age) anni (indicata dall'utente)")
        } else {
            lines.append("Età: non disponibile")
        }

        if let height = snapshot?.heightCm {
            lines.append("Altezza: \(Int(height.rounded())) cm")
        } else if let height = manualHeight {
            lines.append("Altezza: \(Int(height.rounded())) cm (indicata dall'utente)")
        } else {
            lines.append("Altezza: non disponibile")
        }

        if let weight = snapshot?.weightKg {
            var line = "Peso: \(String(format: "%.1f", weight)) kg"
            if let at = snapshot?.weightMeasuredAt { line += " (rilevato il \(formatDate(at)))" }
            lines.append(line)
        } else if let weight = manualWeight {
            lines.append("Peso: \(String(format: "%.1f", weight)) kg (indicato dall'utente)")
        } else {
            lines.append("Peso: non disponibile")
        }

        if let blood = profile?.bloodGroup ?? snapshot?.bloodGroup, !blood.isEmpty {
            lines.append("Gruppo sanguigno: \(blood)")
        }
        if let allergies = profile?.allergies, !allergies.isEmpty {
            lines.append("Allergie registrate: \(allergies)")
        }
        if let notes = profile?.medicalNotes, !notes.isEmpty {
            lines.append("Note mediche: \(notes)")
        }

        if let snapshot {
            if let steps = snapshot.stepsDailyAvg90d {
                lines.append("Passi medi giornalieri (90 giorni): \(Int(steps.rounded()))")
            } else if let steps = snapshot.stepsToday {
                lines.append("Passi di oggi: \(steps)")
            }
            if let minutes = snapshot.weeklyExerciseMinutesAvg {
                lines.append("Minuti di attività settimanali (media): \(Int(minutes.rounded()))")
            }
            if let energy = snapshot.activeEnergyKcal {
                lines.append("Energia attiva recente: \(Int(energy.rounded())) kcal")
            }
            if let vo2 = snapshot.vo2MaxRecent ?? snapshot.vo2Max {
                lines.append("VO2 max: \(String(format: "%.1f", vo2))")
            }
            if let resting = snapshot.restingHeartRateAvg90d ?? snapshot.restingHeartRateBpm {
                lines.append("Frequenza cardiaca a riposo: \(Int(resting.rounded())) bpm")
            }
            lines.append(contentsOf: workoutLines(snapshot.recentWorkouts))
        }

        return lines
    }

    private static func workoutLines(_ workouts: [KBHealthWorkoutEntry]) -> [String] {
        guard !workouts.isEmpty else {
            return ["Allenamenti registrati: nessuno negli ultimi giorni"]
        }
        let sorted = workouts.sorted { $0.startedAt > $1.startedAt }.prefix(12)
        var lines = ["Allenamenti registrati (\(workouts.count), più recenti):"]
        for workout in sorted {
            var line = "• \(workout.title) — \(formatDate(workout.startedAt))"
            if let minutes = workout.durationMinutes { line += ", \(minutes) min" }
            if let kcal = workout.activeEnergyKcal { line += ", \(Int(kcal.rounded())) kcal" }
            lines.append(line)
        }
        return lines
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Lingua risposta

    /// Nome (in italiano) della lingua in cui l'AI deve rispondere: segue la lingua dell'app.
    static func responseLanguageName() -> String {
        switch kbDeviceLocale().language.languageCode?.identifier {
        case "en": return "inglese"
        case "fr": return "francese"
        case "es": return "spagnolo"
        default:   return "italiano"
        }
    }
}
