//
//  FitnessPlanPromptBuilder.swift
//  KidBox
//
//  System prompt e contenuto utente per il Piano Fitness AI.
//  Come gli altri builder di Salute il prompt resta in italiano: la lingua
//  della RISPOSTA (i testi che l'utente legge nel piano) è imposta a parte.
//
//  A differenza del Piano Alimentare qui l'AI deve rispondere in JSON: il piano
//  popola un calendario con stati, promemoria e riconciliazione con Apple
//  Salute, quindi la prosa non basta.
//

import Foundation

enum FitnessPlanPromptBuilder {

    /// Referti allegati: stesso tetto del Piano Alimentare — serve il quadro
    /// clinico (controindicazioni), non il referto integrale.
    static let refertoMaxChars = 1_200

    /// Quante settimane genera il piano base.
    static let planWeeks = 4

    // MARK: - System prompt

    static func systemPrompt(responseLanguage: String) -> String {
        """
        Agisci come un preparatore atletico basato sull'evidenza, integrato nell'app KidBox.
        Costruisci un piano di allenamento mensile personalizzato leggendo i dati sanitari della
        persona: età, peso, altezza, BMI, referti, patologie in corso, terapie farmacologiche,
        parametri biometrici e allenamenti già registrati.

        LINGUA: \(responseLanguage). Scrivi in questa lingua TUTTI i testi destinati all'utente
        (titoli, esercizi, obiettivi, note). Le CHIAVI del JSON restano in inglese come da schema.

        SICUREZZA CLINICA — è la regola che viene prima di tutte le altre:
        Adatta intensità, esercizi e volumi alle controindicazioni che emergono dai dati.
        Esempi di ragionamento richiesto: con ernia discale o lombalgia niente carichi assiali sulla
        colonna (stacchi, squat con bilanciere, military press in piedi) e preferenza per lavoro in
        scarico; con terapie che alterano la frequenza cardiaca (beta-bloccanti, antiaritmici) niente
        lavoro ad alta intensità e sforzo regolato sulla percezione invece che sui battiti; con
        patologie cardiovascolari, respiratorie, metaboliche o articolari riduci l'impatto e la
        progressione; in gravidanza o allattamento niente lavoro ad alta intensità o supino prolungato.
        Ogni adattamento che fai per un motivo clinico DEVE comparire in "safetyNotes", citando il dato
        che lo ha motivato. Se non emergono controindicazioni, scrivilo esplicitamente in una nota.
        Se la persona ha meno di 18 anni, proponi solo attività ludico-motoria e rimanda al pediatra.
        NON formulare diagnosi e NON inventare valori clinici assenti dai dati.

        COSTRUZIONE DEL PIANO:
        Genera esattamente \(planWeeks) settimane, con progressione settimanale sensata (carico che
        cresce e una settimana di scarico se il volume è alto).
        Allena SOLO nei giorni indicati come disponibili: ogni sessione deve avere un "dayOffset"
        compreso nell'elenco di offset ammessi fornito nel messaggio utente. Non inventare altri giorni.
        UNA SOLA seduta per giorno: ogni "dayOffset" compare al massimo una volta in tutto il piano.
        Il lavoro complementare (forza, mobilità, riscaldamento) va dentro la seduta di quel giorno,
        mai in una seduta separata sullo stesso giorno.
        Ogni sessione deve avere esercizi o attività concrete e obiettivi MISURABILI (minuti, distanza,
        calorie, serie × ripetizioni, ritmo). Niente obiettivi generici tipo "allenati bene".
        Rispetta la durata indicata per sessione, con una tolleranza di ±10 minuti.
        Se la persona indica degli sport, quelli sono la materia del piano: le sedute devono essere
        fatte di quelle attività, non di un generico circuito in palestra. Vale per ogni obiettivo,
        anche quando non c'è nessuna gara: chi vuole solo tonicità e salute e indica tennis e bici
        deve ritrovarsi tennis e bici nel calendario, con il lavoro complementare che serve a
        sostenerli. Se gli sport indicati non bastano a coprire l'obiettivo, aggiungi il minimo
        necessario e spiega in "notes" perché.
        Se l'obiettivo è una gara, struttura il mese come un blocco di preparazione verso quella data.

        FORMATO DELLA RISPOSTA — obbligatorio:
        Rispondi con UN SOLO oggetto JSON valido, senza testo prima o dopo, senza Markdown, senza
        blocchi di codice. Nessun commento. Usa esattamente queste chiavi:

        {
          "summary": "3-4 frasi sul piano e sulla logica di progressione",
          "safetyNotes": ["adattamenti clinici, uno per stringa"],
          "weeks": [
            {
              "index": 1,
              "focus": "obiettivo della settimana in una riga",
              "sessions": [
                {
                  "dayOffset": 0,
                  "title": "titolo breve della seduta",
                  "activityType": "corsa | forza | mobilità | cardio | riposo attivo",
                  "durationMinutes": 45,
                  "intensity": "bassa | media | alta",
                  "exercises": [
                    {"name": "nome esercizio", "detail": "3 serie x 12 ripetizioni", "notes": "opzionale"}
                  ],
                  "targets": ["obiettivo misurabile 1", "obiettivo misurabile 2"],
                  "targetKcal": 350,
                  "notes": "nota breve, opzionale"
                }
              ]
            }
          ]
        }

        LUNGHEZZA: massimo 4 esercizi e 3 obiettivi per sessione, testi brevi. L'intero JSON deve
        restare sotto le 1800 parole: meglio sessioni asciutte che un JSON troncato a metà, che il
        client non riuscirebbe a leggere. Devi arrivare fino alla chiusura del JSON.
        """
    }

    // MARK: - User content

    static func userContent(
        subjectName: String,
        input: FitnessPlanInput,
        startDate: Date,
        allowedDayOffsets: [Int],
        profileSummary: [String],
        healthContext: String,
        previousPlan: FitnessPlanDocument? = nil
    ) -> String {
        var lines: [String] = []
        if let previousPlan {
            lines.append(
                "Crea il piano di allenamento del mese \(previousPlan.cycleNumber + 1) per \(subjectName): "
                + "è la continuazione del piano appena concluso, descritto più sotto."
            )
        } else {
            lines.append("Crea il piano di allenamento mensile per \(subjectName).")
        }
        lines.append("")
        lines.append("--- OBIETTIVO E DISPONIBILITÀ ---")
        lines.append("Obiettivo principale: \(input.goal.promptLabel)")

        let sports = input.sortedSports
        if sports.isEmpty {
            lines.append(
                "Sport preferiti: non indicati, scegli tu le attività più adatte all'obiettivo."
            )
        } else {
            lines.append(
                "Sport che la persona vuole praticare: "
                + sports.map(\.promptLabel).joined(separator: ", ")
            )
            lines.append(
                "Costruisci le sedute attorno a questi sport. Aggiungi forza, mobilità o cardio "
                + "solo dove servono per completare l'obiettivo o per prevenire gli infortuni tipici "
                + "di queste discipline, spiegandolo nella seduta."
            )
        }

        if input.goal == .race {
            var race = "Tipo di gara/evento: "
            race += input.raceType?.racePromptLabel ?? "non specificato"
            let detail = input.raceDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty { race += " — \(detail)" }
            lines.append(race)
            if let raceDate = input.raceDate,
               raceDate < Calendar.current.startOfDay(for: Date()) {
                // Succede proprio al mese successivo: la gara era il traguardo
                // del piano concluso e le impostazioni sono rimaste quelle.
                lines.append(
                    "Data della gara: \(formatDate(raceDate)), già passata. Imposta il mese come "
                    + "recupero attivo e poi ripresa, salvo indicazioni diverse nelle note."
                )
            } else if let raceDate = input.raceDate {
                let weeks = max(0, Calendar.current.dateComponents(
                    [.weekOfYear], from: Date(), to: raceDate
                ).weekOfYear ?? 0)
                lines.append("Data della gara: \(formatDate(raceDate)) (tra circa \(weeks) settimane)")
            } else {
                lines.append("Data della gara: non indicata, imposta una preparazione generica.")
            }
        }

        lines.append("Esperienza: \(input.experience.promptLabel)")
        lines.append("Luogo di allenamento: \(input.place.promptLabel)")
        lines.append("Durata per sessione: circa \(input.sessionMinutes) minuti")
        lines.append("Giorni disponibili: \(weekdayNames(input.sortedWeekdays))")
        lines.append("Inizio del piano: \(formatDate(startDate)) (dayOffset 0)")
        lines.append(
            "Offset dei giorni ammessi (giorni trascorsi dall'inizio del piano): "
            + allowedDayOffsets.map(String.init).joined(separator: ", ")
        )

        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("Note dell'utente (infortuni, limiti, preferenze): \(notes)")
        }

        if let previousPlan {
            lines.append("")
            lines.append(contentsOf: previousPlanLines(previousPlan))
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

    // MARK: - Mese precedente

    /// Il piano concluso raccontato all'AI: i numeri del consuntivo, l'ultima
    /// settimana seduta per seduta (è il livello da cui ripartire) e i mesi
    /// ancora prima in una riga ciascuno. Poche centinaia di caratteri: non
    /// sposta le unità del piano, che restano al minimo di 5 × 3.
    static func previousPlanLines(_ plan: FitnessPlanDocument) -> [String] {
        let recap = FitnessWeeklyReportBuilder.recap(plan: plan)
        var lines: [String] = []
        lines.append(
            "--- MESE PRECEDENTE (mese \(plan.cycleNumber), dal \(formatDate(recap.startDate)) "
            + "al \(formatDate(recap.endDate))) ---"
        )
        lines.append("Obiettivo di quel mese: \(recap.goal.promptLabel)")
        lines.append(
            "Sedute completate: \(recap.completedSessions) su \(recap.plannedSessions) "
            + "(\(recap.completionPercent)%), saltate \(recap.skippedSessions), "
            + "fatte con un'attività diversa da quella prevista \(recap.substitutedSessions)"
        )
        lines.append(
            "Completamento per settimana: "
            + recap.weeklyCompletionPercents.map { "\($0)%" }.joined(separator: ", ")
        )
        var volume = "Volume svolto: \(recap.totalMinutes) minuti"
        if recap.totalDistanceMeters >= 10 {
            volume += String(format: ", %.1f km", recap.totalDistanceMeters / 1000)
        }
        if recap.totalKcal > 0 { volume += ", \(recap.totalKcal) kcal" }
        lines.append(volume)
        if !recap.chronicallySkippedWeekdays.isEmpty {
            lines.append("Giorni saltati più volte: \(weekdayNames(recap.chronicallySkippedWeekdays))")
        }
        if recap.extraWorkouts > 0 {
            var counts: [String: Int] = [:]
            for workout in plan.logged { counts[workout.title, default: 0] += 1 }
            let ranked: [(String, Int)] = counts.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            let titles: [String] = ranked.prefix(4).map { "\($0.0) ×\($0.1)" }
            lines.append(
                "Attività registrate fuori programma: \(recap.extraWorkouts) ("
                + titles.joined(separator: ", ") + ")"
            )
        }

        if let lastWeek = plan.weeks.max(by: { $0.index < $1.index }) {
            lines.append("Sedute dell'ultima settimana (il livello da cui ripartire):")
            for session in lastWeek.sessions.sorted(by: { $0.date < $1.date }) where !session.isRest {
                lines.append("- " + sessionOutcomeLine(session))
            }
        }

        // I mesi più vecchi restano nel documento (sono poche centinaia di
        // byte l'uno) ma al prompt ne bastano gli ultimi, per la tendenza.
        let older = plan.previousCycles ?? []
        let shown = older.suffix(5)
        if !shown.isEmpty {
            lines.append("Mesi ancora precedenti:")
            for (offset, cycle) in shown.enumerated() {
                let number = older.count - shown.count + offset + 1
                lines.append(
                    "- mese \(number) (\(cycle.goal.promptLabel)): \(cycle.completionPercent)% "
                    + "delle sedute, \(cycle.totalMinutes) minuti"
                )
            }
        }

        lines.append("")
        lines.append("REGOLE PER LA CONTINUAZIONE:")
        lines.append(
            "- Riparti dal livello raggiunto nell'ultima settimana, non da zero: niente settimana "
            + "introduttiva se la persona si è allenata con continuità."
        )
        lines.append(
            "- Completamento del mese dal 70% in su: progressione moderata (circa +10% di volume o "
            + "una seduta più impegnativa). Dal 40% al 69%: stesso volume, consolida. Sotto il 40%: "
            + "riduci durata o numero di sedute e rendile più facili da incastrare."
        )
        lines.append(
            "- Nei giorni saltati più volte metti le sedute più brevi o leggere, se restano fra "
            + "quelli disponibili."
        )
        lines.append(
            "- Le attività fatte al posto di quelle previste e quelle fuori programma dicono cosa la "
            + "persona fa volentieri: dagli spazio nel nuovo mese."
        )
        lines.append(
            "- Mantieni le discipline ma varia esercizi e stimoli rispetto al mese precedente."
        )
        lines.append(
            "- Il campo \"summary\" si apre con 1-2 frasi di bilancio del mese concluso, con i numeri, "
            + "e spiega come il nuovo mese ne tiene conto."
        )
        return lines
    }

    /// Una seduta dell'ultima settimana come la legge l'AI: prevista e svolta.
    private static func sessionOutcomeLine(_ session: FitnessSession) -> String {
        var line = "\(session.title) (\(session.activityType), \(session.durationMinutes) min, "
            + "intensità \(session.intensity)): "
        switch session.status {
        case .done:
            var outcome = ["completata"]
            if let minutes = session.actualMinutes { outcome.append("\(minutes) min") }
            if let meters = session.actualDistanceMeters, meters >= 10 {
                outcome.append(String(format: "%.1f km", meters / 1000))
            }
            if session.wasSubstituted, let actual = session.actualActivityTitle {
                outcome.append("svolta come \(actual)")
            }
            line += outcome.joined(separator: ", ")
        case .skipped:
            line += "saltata"
        case .planned, .moved:
            line += "non registrata"
        }
        return line
    }

    // MARK: - Ricalcolo dopo uno spostamento

    /// Prompt breve per la logica "Sposta": costa poche unità perché non
    /// rimanda il contesto clinico completo, solo le sessioni della settimana.
    static func rescheduleSystemPrompt(responseLanguage: String) -> String {
        """
        Sei il preparatore atletico dell'app KidBox. L'utente ha spostato una seduta.
        Riorganizza SOLO le sedute rimanenti della settimana indicata, senza aumentare il carico
        totale e senza mettere due sedute intense di fila. Non toccare le sedute già completate.
        LINGUA dei testi: \(responseLanguage).

        Rispondi con UN SOLO oggetto JSON valido, niente testo attorno, niente Markdown:
        {
          "rationale": "una riga sul criterio usato",
          "sessions": [
            {
              "id": "id della seduta esistente",
              "dayOffset": 3,
              "title": "…",
              "activityType": "…",
              "durationMinutes": 45,
              "intensity": "…",
              "exercises": [{"name": "…", "detail": "…"}],
              "targets": ["…"],
              "targetKcal": 300,
              "notes": "…"
            }
          ]
        }
        Includi solo le sedute che cambiano, con l'id identico a quello ricevuto.
        """
    }

    /// Prompt breve per la proposta di adeguamento di fine settimana.
    static func weeklyAdjustSystemPrompt(responseLanguage: String) -> String {
        """
        Sei il preparatore atletico dell'app KidBox. Analizza l'andamento della settimana appena
        conclusa e proponi come impostare la settimana successiva. Tieni conto dei giorni saltati in
        modo sistematico, dei dati biometrici e delle controindicazioni cliniche già note.
        LINGUA dei testi: \(responseLanguage).

        Rispondi con UN SOLO oggetto JSON valido, niente testo attorno, niente Markdown:
        {
          "rationale": "2-3 frasi sul perché di queste modifiche",
          "changes": ["modifica proposta 1", "modifica proposta 2"],
          "sessions": [
            {
              "id": "id della seduta da riscrivere",
              "dayOffset": 10,
              "title": "…",
              "activityType": "…",
              "durationMinutes": 45,
              "intensity": "…",
              "exercises": [{"name": "…", "detail": "…"}],
              "targets": ["…"],
              "targetKcal": 300,
              "notes": "…"
            }
          ]
        }
        Includi solo le sedute della settimana successiva che vuoi modificare, con l'id ricevuto.
        Se non serve cambiare nulla, restituisci "sessions": [] spiegando il perché in "rationale".
        """
    }

    // MARK: - Profilo

    /// Righe compatte su età, altezza, peso e allenamenti recenti.
    /// Riusa il builder del Piano Alimentare: la fotografia antropometrica è la stessa.
    static func profileSummaryLines(
        birthDate: Date?,
        snapshot: KBHealthImportSnapshot?,
        profile: KBPediatricProfile?,
        input: FitnessPlanInput
    ) -> [String] {
        var lines = MealPlanPromptBuilder.profileSummaryLines(
            birthDate: birthDate,
            snapshot: snapshot,
            profile: profile,
            manualAge: input.manualAgeValue,
            manualWeight: input.manualWeightValue,
            manualHeight: input.manualHeightValue
        )
        if let bmi = bmiLine(snapshot: snapshot, input: input) {
            lines.append(bmi)
        }
        return lines
    }

    private static func bmiLine(snapshot: KBHealthImportSnapshot?, input: FitnessPlanInput) -> String? {
        guard
            let weight = snapshot?.weightKg ?? input.manualWeightValue,
            let heightCm = snapshot?.heightCm ?? input.manualHeightValue,
            heightCm > 0
        else { return nil }
        let heightM = heightCm / 100
        let bmi = weight / (heightM * heightM)
        return String(format: "BMI calcolato: %.1f", bmi)
    }

    // MARK: - Utility

    static func weekdayNames(_ weekdays: [Int]) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        let symbols = formatter.standaloneWeekdaySymbols ?? []
        let names = weekdays.compactMap { index -> String? in
            guard index >= 1, index <= symbols.count else { return nil }
            return symbols[index - 1]
        }
        return names.isEmpty ? "nessuno" : names.joined(separator: ", ")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Nome (in italiano) della lingua in cui l'AI deve rispondere: segue la lingua dell'app.
    static func responseLanguageName() -> String {
        MealPlanPromptBuilder.responseLanguageName()
    }
}
