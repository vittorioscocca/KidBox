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

        private enum CodingKeys: String, CodingKey { case name, detail, notes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            detail = c.lenientString(.detail)
            notes = c.lenientString(.notes)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, date, title, activityType, durationMinutes, intensity
        case exercises, targets, targetKcal, notes, status
    }

    /// Decodifica tollerante: un campo scritto male («40» fra virgolette, 40.0,
    /// un esercizio senza nome) non deve far cadere l'intera azione, e con lei
    /// tutte le altre del blocco.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        // Il prompt elenca le sedute come `id=…`: il modello a volte copia
        // anche il prefisso.
        sessionId = c.lenientString(.sessionId).map {
            $0.hasPrefix("id=") ? String($0.dropFirst(3)) : $0
        }
        date = c.lenientString(.date)
        title = c.lenientString(.title)
        activityType = c.lenientString(.activityType)
        durationMinutes = c.lenientInt(.durationMinutes)
        intensity = c.lenientString(.intensity)
        exercises = (try? c.decode([FailableDecodable<Exercise>].self, forKey: .exercises))?
            .compactMap(\.value)
        targets = (try? c.decode([FailableDecodable<String>].self, forKey: .targets))?
            .compactMap(\.value)
        targetKcal = c.lenientInt(.targetKcal)
        notes = c.lenientString(.notes)
        status = c.lenientString(.status)
    }
}

private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let string = try? decode(String.self, forKey: key) { return string }
        if let int = try? decode(Int.self, forKey: key) { return String(int) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let int = try? decode(Int.self, forKey: key) { return int }
        if let double = try? decode(Double.self, forKey: key) { return Int(double.rounded()) }
        if let string = try? decode(String.self, forKey: key) {
            let digits = string.prefix { $0.isNumber }
            return Int(digits)
        }
        return nil
    }
}

struct FitnessCopilotProcessedReply {
    let displayText: String
    let plan: FitnessPlanDocument
    /// Riepilogo delle modifiche applicate, `nil` se non è cambiato nulla.
    let executionSummary: String?
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
        let extracted = extractActions(from: reply)
        let display = extracted.displayText
        let actions = extracted.actions

        // Nessun blocco: la risposta è solo testo.
        guard extracted.blockFound else {
            return FitnessCopilotProcessedReply(
                displayText: display,
                plan: plan,
                executionSummary: nil,
                failedActions: 0
            )
        }

        var updated = plan
        var applied: [String] = []

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
                let activityType = action.activityType ?? action.title ?? ""
                let title = action.title ?? activityType
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

            switch action.type {
            // Si applica subito come le altre: la richiesta in chat è già la
            // conferma dell'utente. Con l'alert intermedio il modello scriveva
            // "ho eliminato" e la seduta restava sul calendario.
            case "delete_session":
                updated.removeSession(id: sessionId)
                applied.append(
                    String(
                        format: NSLocalizedString(
                            "Seduta del %@ eliminata",
                            comment: "Fitness copilot deleted session"
                        ),
                        FitnessPlanFormat.mediumDate(existing.date)
                    )
                )

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
            failedActions: max(0, actions.count - applied.count) + extracted.undecodable
        )
    }

    private struct ExtractedActions {
        var displayText: String
        var actions: [FitnessCopilotAction]
        /// Azioni (o blocchi interi) che c'erano ma non si sono potute leggere.
        var undecodable: Int
        var blockFound: Bool
    }

    /// Estrae **tutti** i blocchi di azioni dalla risposta.
    ///
    /// Tre modi in cui una modifica annunciata andava persa senza avviso:
    /// - il modello spezza le azioni in più blocchi, e si leggeva solo il primo;
    /// - la risposta viene troncata dal limite di token prima del marcatore di
    ///   chiusura, e il blocco non veniva nemmeno riconosciuto (né rimosso dal
    ///   testo, né segnalato);
    /// - un solo campo malformato faceva scartare l'intero array.
    private static func extractActions(from reply: String) -> ExtractedActions {
        var display = ""
        var actions: [FitnessCopilotAction] = []
        var undecodable = 0
        var blockFound = false
        var cursor = reply.startIndex

        while let startRange = reply.range(of: FitnessCopilotActionMarkers.start, range: cursor..<reply.endIndex) {
            blockFound = true
            display += reply[cursor..<startRange.lowerBound]
            guard let endRange = reply.range(
                of: FitnessCopilotActionMarkers.end,
                range: startRange.upperBound..<reply.endIndex
            ) else {
                // Blocco troncato: quel che resta non è testo da mostrare, e le
                // azioni complete che contiene non sono affidabili.
                KBLog.ai.kbError("FitnessCopilot: blocco azioni senza chiusura (risposta troncata?)")
                undecodable += 1
                cursor = reply.endIndex
                break
            }
            let decoded = decodeActions(String(reply[startRange.upperBound..<endRange.lowerBound]))
            actions += decoded.actions
            undecodable += decoded.undecodable
            cursor = endRange.upperBound
        }
        display += reply[cursor..<reply.endIndex]

        return ExtractedActions(
            displayText: display.trimmingCharacters(in: .whitespacesAndNewlines),
            actions: actions,
            undecodable: undecodable,
            blockFound: blockFound
        )
    }

    private static func decodeActions(_ raw: String) -> (actions: [FitnessCopilotAction], undecodable: Int) {
        var json = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Recinzione Markdown attorno al JSON.
        if json.hasPrefix("```") {
            json = json.drop(while: { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
            if json.hasSuffix("```") { json = String(json.dropLast(3)) }
        }

        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else {
            KBLog.ai.kbError("FitnessCopilot: blocco azioni non decodificabile")
            return ([], 1)
        }

        // Array di azioni, singola azione, oppure `{"actions": [...]}`.
        let elements: [Any]
        if let array = root as? [Any] {
            elements = array
        } else if let object = root as? [String: Any], let nested = object["actions"] as? [Any] {
            elements = nested
        } else if let object = root as? [String: Any] {
            elements = [object]
        } else {
            return ([], 1)
        }

        var actions: [FitnessCopilotAction] = []
        var undecodable = 0
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let action = try? JSONDecoder().decode(FitnessCopilotAction.self, from: elementData)
            else {
                undecodable += 1
                continue
            }
            actions.append(action)
        }
        if undecodable > 0 {
            KBLog.ai.kbError("FitnessCopilot: \(undecodable) azioni non decodificabili")
        }
        return (actions, undecodable)
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
