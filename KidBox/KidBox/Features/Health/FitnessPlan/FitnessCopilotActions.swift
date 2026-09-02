//
//  FitnessCopilotActions.swift
//  KidBox
//
//  Capacità operative del copilota: l'AI non si limita a rispondere, può
//  modificare il piano.
//
//  Il meccanismo è quello già usato dalle altre chat KidBox
//  (`PlanningAIActionBlock`): l'assistente allega alla risposta un blocco JSON
//  fra due marcatori, il client lo esegue e lo rimuove dal testo mostrato. I
//  marcatori sono dedicati al fitness, così il pipeline di planning non prova a
//  eseguire azioni che non conosce.
//

import Foundation

enum FitnessCopilotActionMarkers {
    static let start = "<<<KIDBOX_FITNESS_ACTIONS>>>"
    static let end = "<<<END_KIDBOX_FITNESS_ACTIONS>>>"
}

struct FitnessCopilotAction: Decodable {
    /// `replace_session`, `move_session`, `mark_session`, `add_session`, `delete_session`.
    let type: String
    let sessionId: String?
    let date: String?
    let title: String?
    let activityType: String?
    let durationMinutes: Int?
    let intensity: String?
    let exercises: [Exercise]?
    let targets: [String]?
    let targetKcal: Int?
    let notes: String?
    let status: String?

    struct Exercise: Decodable {
        let name: String
        let detail: String?
        let notes: String?
    }
}

struct FitnessCopilotProcessedReply {
    let displayText: String
    let plan: FitnessPlanDocument
    /// Riepilogo delle modifiche applicate, `nil` se non è cambiato nulla.
    let executionSummary: String?
    /// Sedute che l'AI vuole eliminare: **non** ancora rimosse dal piano.
    ///
    /// L'eliminazione è l'unica azione che non si applica da sola. Le altre
    /// sono rimediabili — una seduta spostata si rimette a posto, una segnata
    /// per errore si riapre — mentre una seduta cancellata non torna indietro:
    /// l'ultima parola resta all'utente.
    let pendingDeletions: [FitnessSession]
    /// Azioni allegate alla risposta che non è stato possibile eseguire.
    ///
    /// Serve a non lasciar passare una conferma falsa: il testo discorsivo dice
    /// "ho spostato la seduta" anche quando l'id era inventato o il JSON era
    /// malformato, e senza questo l'utente se ne accorgerebbe solo tornando sul
    /// calendario.
    let failedActions: Int
}

enum FitnessCopilotActionExecutor {

    /// Estrae le azioni dalla risposta, le applica al piano e restituisce il
    /// testo ripulito da mostrare in chat.
    static func process(_ reply: String, plan: FitnessPlanDocument) -> FitnessCopilotProcessedReply {
        guard
            let startRange = reply.range(of: FitnessCopilotActionMarkers.start),
            let endRange = reply.range(
                of: FitnessCopilotActionMarkers.end,
                range: startRange.upperBound..<reply.endIndex
            )
        else {
            return FitnessCopilotProcessedReply(
                displayText: reply.trimmingCharacters(in: .whitespacesAndNewlines),
                plan: plan,
                executionSummary: nil,
                pendingDeletions: [],
                failedActions: 0
            )
        }

        let json = reply[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var display = reply
        display.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        display = display.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let data = json.data(using: .utf8),
            let actions = try? JSONDecoder().decode([FitnessCopilotAction].self, from: data),
            !actions.isEmpty
        else {
            KBLog.ai.kbError("FitnessCopilot: blocco azioni non decodificabile")
            // Il blocco c'era: la risposta parla di una modifica che non è
            // avvenuta, e va segnalato.
            return FitnessCopilotProcessedReply(
                displayText: display,
                plan: plan,
                executionSummary: nil,
                pendingDeletions: [],
                failedActions: 1
            )
        }

        var updated = plan
        var applied: [String] = []
        var pendingDeletions: [FitnessSession] = []

        for action in actions {
            // L'aggiunta è l'unica azione che non parte da una seduta esistente:
            // va gestita prima del controllo sul sessionId.
            if action.type == "add_session" {
                guard
                    let newDate = parseDate(action.date),
                    // Fuori dall'orizzonte del piano non c'è settimana in cui
                    // metterla: meglio non applicarla che inventarne una.
                    let weekIndex = updated.weekIndex(for: newDate),
                    let target = updated.weeks.firstIndex(where: { $0.index == weekIndex })
                else { continue }
                let title = action.title ?? ""
                let activityType = action.activityType ?? ""
                guard !title.isEmpty, !activityType.isEmpty else { continue }

                updated.weeks[target].sessions.append(
                    FitnessSession(
                        date: newDate,
                        weekIndex: weekIndex,
                        title: title,
                        activityType: activityType,
                        durationMinutes: max(10, action.durationMinutes ?? 45),
                        intensity: action.intensity ?? "",
                        exercises: (action.exercises ?? []).map {
                            FitnessExercise(name: $0.name, detail: $0.detail ?? "", notes: $0.notes)
                        },
                        targets: action.targets ?? [],
                        targetKcal: action.targetKcal,
                        notes: action.notes
                    )
                )
                applied.append(
                    String(
                        format: NSLocalizedString(
                            "Seduta aggiunta il %@",
                            comment: "Fitness copilot added a session"
                        ),
                        FitnessPlanFormat.mediumDate(newDate)
                    )
                )
                continue
            }

            guard let sessionId = action.sessionId,
                  let existing = updated.session(id: sessionId)
            else { continue }

            // L'eliminazione non si applica qui: si mette in attesa di conferma.
            if action.type == "delete_session" {
                pendingDeletions.append(existing)
                continue
            }

            switch action.type {
            case "replace_session":
                updated.updateSession(id: sessionId) { session in
                    if let title = action.title, !title.isEmpty { session.title = title }
                    if let type = action.activityType, !type.isEmpty { session.activityType = type }
                    if let minutes = action.durationMinutes, minutes > 0 {
                        session.durationMinutes = minutes
                    }
                    if let intensity = action.intensity { session.intensity = intensity }
                    if let exercises = action.exercises {
                        session.exercises = exercises.map {
                            FitnessExercise(name: $0.name, detail: $0.detail ?? "", notes: $0.notes)
                        }
                    }
                    if let targets = action.targets { session.targets = targets }
                    if let kcal = action.targetKcal { session.targetKcal = kcal }
                    if let notes = action.notes { session.notes = notes }
                    session.status = .planned
                }
                applied.append(
                    String(
                        format: NSLocalizedString(
                            "Seduta del %@ sostituita",
                            comment: "Fitness copilot replaced session"
                        ),
                        FitnessPlanFormat.mediumDate(existing.date)
                    )
                )

            case "move_session":
                guard let newDate = parseDate(action.date) else { continue }
                updated.updateSession(id: sessionId) { session in
                    session.originalDate = session.originalDate ?? session.date
                    session.date = newDate
                    session.status = .planned
                }
                applied.append(
                    String(
                        format: NSLocalizedString(
                            "Seduta spostata al %@",
                            comment: "Fitness copilot moved session"
                        ),
                        FitnessPlanFormat.mediumDate(newDate)
                    )
                )

            case "mark_session":
                guard let raw = action.status,
                      let status = FitnessSessionStatus(rawValue: raw)
                else { continue }
                updated.updateSession(id: sessionId) { session in
                    session.status = status
                    session.completedAt = status == .done ? Date() : nil
                    session.completionSource = status == .done ? .manual : nil
                }
                applied.append(
                    String(
                        format: NSLocalizedString(
                            "Seduta del %@ aggiornata",
                            comment: "Fitness copilot updated session status"
                        ),
                        FitnessPlanFormat.mediumDate(existing.date)
                    )
                )

            default:
                KBLog.ai.kbInfo("FitnessCopilot: azione ignota type=\(action.type)")
            }
        }

        for weekIndex in updated.weeks.indices {
            updated.weeks[weekIndex].sessions.sort { $0.date < $1.date }
        }

        return FitnessCopilotProcessedReply(
            displayText: display,
            plan: updated,
            executionSummary: applied.isEmpty ? nil : applied.joined(separator: " · "),
            pendingDeletions: pendingDeletions,
            // Un'eliminazione in attesa non è un fallimento: è stata capita, e
            // aspetta solo l'ultima parola dell'utente.
            failedActions: max(0, actions.count - applied.count - pendingDeletions.count)
        )
    }

    /// Data in formato `yyyy-MM-dd`, come richiesto nel system prompt.
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let date = formatter.date(from: raw) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }
}
