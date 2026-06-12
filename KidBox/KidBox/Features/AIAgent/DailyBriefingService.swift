//
//  DailyBriefingService.swift
//  KidBox
//
//  Genera automaticamente un briefing mattutino della famiglia usando l'AI
//  e lo recapita come notifica locale ogni giorno alle 08:00.
//
//  Flusso (speculare a WeeklySummaryService):
//  1. `scheduleDailyIfNeeded()` — all'avvio / cambio famiglia attiva.
//  2. Se manca il briefing di oggi, chiama AIService.
//  3. Salva testo in UserDefaults e schedula notifica giornaliera.
//  4. Al tap: `NotificationManager` → `.askExpert` con testo in chat.
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
final class DailyBriefingService {

    static let shared = DailyBriefingService()
    private init() {}

    private enum Keys {
        static let lastISODate = "kb_dailyBriefing_lastISODate"
        static let lastText    = "kb_dailyBriefing_lastText"
        static let enabled     = "kb_dailyBriefingEnabled"
        static let notifId     = "kb_dailyBriefing_notifId"
    }

    // MARK: - Public API

    func scheduleDailyIfNeeded(
        input: PlanningContextInput,
        familyName: String,
        modelContext: ModelContext,
        forcedFamilyId: String? = nil
    ) async {
        _ = modelContext
        let familyId = forcedFamilyId ?? ""

        guard isEnabled else {
            KBLog.ai.kbDebug("DailyBriefingService: disabled by user preference")
            return
        }
        guard AISettings.shared.isEnabled else {
            KBLog.ai.kbDebug("DailyBriefingService: AI globally disabled")
            return
        }

        let today = isoDateKey()
        let lastDay = UserDefaults.standard.string(forKey: Keys.lastISODate) ?? ""

        guard today != lastDay else {
            KBLog.ai.kbDebug("DailyBriefingService: briefing already generated for \(today)")
            if let text = UserDefaults.standard.string(forKey: Keys.lastText) {
                await scheduleLocalNotification(briefingText: text, familyName: familyName, familyId: familyId)
            }
            return
        }

        KBLog.ai.kbInfo("DailyBriefingService: generating briefing for \(today)")
        await generateAndSchedule(input: input, familyName: familyName, dateKey: today, familyId: familyId)
    }

    var lastBriefingText: String? {
        UserDefaults.standard.string(forKey: Keys.lastText)
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }

    // MARK: - Generation

    private func generateAndSchedule(
        input: PlanningContextInput,
        familyName: String,
        dateKey: String,
        familyId: String
    ) async {
        let systemPrompt = buildDailyBriefingPrompt(familyName: familyName)
        let userMessage = buildDailyDataMessage(input: input)

        let aiMessages = [KBAIMessage(role: .user, content: userMessage)]

        do {
            let response = try await AIService.shared.sendMessage(
                messages: aiMessages,
                systemPrompt: systemPrompt
            )

            let text = response.reply
            KBLog.ai.kbInfo("DailyBriefingService: generated chars=\(text.count)")

            UserDefaults.standard.set(dateKey, forKey: Keys.lastISODate)
            UserDefaults.standard.set(text, forKey: Keys.lastText)

            await scheduleLocalNotification(briefingText: text, familyName: familyName, familyId: familyId)
        } catch {
            KBLog.ai.kbError("DailyBriefingService: generation failed \(error.localizedDescription)")
        }
    }

    // MARK: - System prompt

    private func buildDailyBriefingPrompt(familyName: String) -> String {
        """
        Sei l'assistente AI di KidBox per la famiglia \(familyName).
        Genera un briefing del mattino ULTRA-BREVE (max 5 bullet) focalizzato \
        SOLO su oggi e domani.

        REGOLE:
        - Scrivi in italiano, tono pratico e diretto, come un assistente di famiglia.
        - Da 3 a 5 punti bullet (•), ognuno su una riga.
        - Ogni punto: max 12 parole.
        - Zero intestazioni, zero markdown, zero intro.
        - Priorità nel selezionare i punti: eventi di oggi/domani con orario, \
        dosi medicine oggi, todo in scadenza, scadenze critiche salute, \
        scadenze veicolo (assicurazione/bollo/revisione), vaccini in arrivo, \
        pagamenti casa in scadenza e compleanni nelle prossime 48h.
        - Se i punti rilevanti superano 5, tieni i più urgenti/importanti.
        - I compleanni vanno sempre evidenziati con tono caloroso (es. 🎂).
        - Termina SEMPRE con una riga vuota e poi una singola domanda:
          "Cosa vuoi organizzare oggi?"
        - Se non c'è nulla di rilevante: "Giornata libera da impegni. Buona giornata!"
        """
    }

    // MARK: - Data message (prossime 48h)

    private func buildDailyDataMessage(input: PlanningContextInput) -> String {
        var lines: [String] = ["Genera il briefing del mattino basandoti su questi dati:\n"]

        let now = Date()
        let horizon = now.addingTimeInterval(48 * 60 * 60)
        let cal = Calendar.current

        let dayFmt = DateFormatter()
        dayFmt.locale = kbDeviceLocale()
        dayFmt.dateStyle = .medium
        dayFmt.timeStyle = .none

        let timeFmt = DateFormatter()
        timeFmt.locale = kbDeviceLocale()
        timeFmt.dateFormat = "HH:mm"

        lines.append("Oggi: \(dayFmt.string(from: now))\n")

        let events = input.calendarEvents.filter {
            !$0.isDeleted && $0.startDate >= now && $0.startDate <= horizon
        }.sorted { $0.startDate < $1.startDate }

        if !events.isEmpty {
            lines.append("EVENTI (oggi e domani):")
            for event in events.prefix(12) {
                let dayLabel = cal.isDateInToday(event.startDate)
                    ? "oggi"
                    : (cal.isDateInTomorrow(event.startDate) ? "domani" : dayFmt.string(from: event.startDate))
                lines.append("  • \(dayLabel) \(timeFmt.string(from: event.startDate)) — \(event.title)")
            }
        }

        let activeTreatments = input.activeTreatments.filter { !$0.isDeleted && $0.isActive }
        if !activeTreatments.isEmpty {
            lines.append("\nDOSI MEDICINE OGGI:")
            for treatment in activeTreatments.prefix(8) {
                let child = input.childNames[treatment.childId] ?? treatment.childId
                let times = treatment.scheduleTimes
                if times.isEmpty {
                    lines.append("  • \(treatment.drugName) per \(child)")
                } else {
                    for slot in times {
                        lines.append("  • \(slot): \(treatment.drugName) (\(child))")
                    }
                }
            }
        }

        let dueTodos = input.openTodos.filter { todo in
            guard !todo.isDone, !todo.isDeleted else { return false }
            if (todo.priorityRaw ?? 0) >= 1 { return true }
            guard let due = todo.dueAt else { return false }
            return due >= now && due <= horizon
        }
        if !dueTodos.isEmpty {
            lines.append("\nTO-DO (oggi / urgenti):")
            for todo in dueTodos.prefix(8) {
                var line = "  • \(todo.title)"
                if let due = todo.dueAt {
                    line += " (entro \(dayFmt.string(from: due)))"
                }
                lines.append(line)
            }
        }

        var criticalLines: [String] = []

        for visit in input.visitsWithNextDate where !visit.isDeleted {
            guard let next = visit.nextVisitDate, next >= now, next <= horizon else { continue }
            let child = input.childNames[visit.childId] ?? visit.childId
            criticalLines.append("  • Visita \(child): \(dayFmt.string(from: next))")
        }

        for visit in input.visitsWithPendingExams where !visit.isDeleted {
            for exam in visit.prescribedExams {
                guard let deadline = exam.deadline, deadline >= now, deadline <= horizon else { continue }
                let child = input.childNames[visit.childId] ?? visit.childId
                criticalLines.append("  • Esame \(exam.name) (\(child)): entro \(dayFmt.string(from: deadline))")
            }
        }

        if !criticalLines.isEmpty {
            lines.append("\nSCADENZE CRITICHE (48h):")
            lines.append(contentsOf: criticalLines.prefix(6))
        }

        // Scadenze & promemoria aggiuntivi nelle prossime 48h.
        var extraLines: [String] = []

        // Vaccini in arrivo (programmati / prossima dose).
        for vaccine in input.upcomingVaccines where !vaccine.isDeleted {
            guard vaccine.statusRaw != VaccineStatus.administered.rawValue else { continue }
            guard let when = vaccine.scheduledDate ?? vaccine.nextDoseDate,
                  when >= now, when <= horizon else { continue }
            let child = input.childNames[vaccine.childId] ?? vaccine.childId
            let name = VaccineType(rawValue: vaccine.vaccineTypeRaw)?.displayName ?? "Vaccino"
            extraLines.append("  • Vaccino \(name) (\(child)): \(dayFmt.string(from: when))")
        }

        // Scadenze/interventi veicolo (assicurazione, bollo, revisione, tagliando…).
        let vehicleNames = Dictionary(uniqueKeysWithValues: input.vehicles.map { ($0.id, $0.name) })
        for ev in input.vehicleEvents where !ev.isDeleted {
            guard ev.date >= now, ev.date <= horizon else { continue }
            let veh = vehicleNames[ev.vehicleId] ?? "veicolo"
            extraLines.append("  • \(ev.title) (\(veh)): \(dayFmt.string(from: ev.date))")
        }

        // Pagamenti casa in scadenza (mutuo, affitto, bollette, tasse).
        for payment in input.housePayments where !payment.isDeleted {
            guard let due = payment.earliestDisplayDeadline(from: now),
                  due >= cal.startOfDay(for: now), due <= horizon else { continue }
            extraLines.append("  • \(payment.name): \(dayFmt.string(from: due))")
        }

        if !extraLines.isEmpty {
            lines.append("\nSCADENZE & PROMEMORIA (48h):")
            lines.append(contentsOf: extraLines.prefix(8))
        }

        // Compleanni in famiglia (oggi / domani).
        var birthdayLines: [String] = []
        for child in input.children {
            guard let bd = child.birthDate else { continue }
            let bdComps = cal.dateComponents([.month, .day], from: bd)
            let isToday = cal.dateComponents([.month, .day], from: now) == bdComps
            let tomorrow = now.addingTimeInterval(24 * 60 * 60)
            let isTomorrow = cal.dateComponents([.month, .day], from: tomorrow) == bdComps
            guard isToday || isTomorrow else { continue }
            let age = cal.dateComponents([.year], from: bd, to: isToday ? now : tomorrow).year
            let ageLabel = age.map { " (\($0) anni)" } ?? ""
            birthdayLines.append("  • \(isToday ? "oggi" : "domani"): compleanno di \(child.name)\(ageLabel)")
        }
        if !birthdayLines.isEmpty {
            lines.append("\nCOMPLEANNI:")
            lines.append(contentsOf: birthdayLines)
        }

        lines.append("\nGenera ora il briefing seguendo le regole del sistema.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Local notification

    private func scheduleLocalNotification(
        briefingText: String,
        familyName: String,
        familyId: String
    ) async {
        let center = UNUserNotificationCenter.current()

        if let oldId = UserDefaults.standard.string(forKey: Keys.notifId) {
            center.removePendingNotificationRequests(withIdentifiers: [oldId])
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            KBLog.ai.kbDebug("DailyBriefingService: no notification permission status=\(settings.authorizationStatus.rawValue)")
            return
        @unknown default:
            KBLog.ai.kbDebug("DailyBriefingService: unknown notification permission")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "☀️ Buongiorno, \(familyName)"
        let firstLine = briefingText
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Il tuo briefing del giorno è pronto."
        content.body = firstLine
        content.sound = .default
        var info: [String: Any] = [
            "type": "daily_briefing",
            "fullText": String(briefingText.prefix(500))
        ]
        if !familyId.isEmpty { info["familyId"] = familyId }
        content.userInfo = info

        var dc = DateComponents()
        dc.hour = 8
        dc.minute = 0
        dc.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

        let notifId = "kb-daily-briefing-\(isoDateKey())"
        let request = UNNotificationRequest(
            identifier: notifId,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            UserDefaults.standard.set(notifId, forKey: Keys.notifId)
            KBLog.ai.kbInfo("DailyBriefingService: notification scheduled id=\(notifId)")
        } catch {
            KBLog.ai.kbError("DailyBriefingService: schedule failed \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func isoDateKey() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = Calendar.current.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
