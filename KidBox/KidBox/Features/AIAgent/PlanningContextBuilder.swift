//
//  PlanningContextBuilder.swift
//  KidBox
//
//  Builds the AI system prompt for the family planning agent.
//  Covers calendar events, todo items, routines, active treatments
//  (as time-slots), and upcoming health deadlines (next visits,
//  prescribed exams, scheduled vaccines).
//
//  Design mirrors MedicalVisitContextBuilder / HealthContextBuilder:
//  - Static enum, no stored state.
//  - Caller passes already-fetched SwiftData objects.
//  - Window-based: only items within `horizon` days are included,
//    keeping the prompt lean and focused.
//

import Foundation

// MARK: - Input

/// Everything the planning agent needs. Callers fill only what is
/// relevant to the current question; unused arrays can stay empty.
struct PlanningContextInput {
    
    // ── Family identity ───────────────────────────────────────────
    let familyName:  String
    /// Display names keyed by uid — used to resolve `assignedTo`.
    let memberNames: [String: String]
    
    // ── Time window ───────────────────────────────────────────────
    /// How many days ahead to include.  Default 14, max 90.
    let horizonDays: Int
    
    // ── Calendar ──────────────────────────────────────────────────
    let calendarEvents: [KBCalendarEvent]
    
    // ── Todo ──────────────────────────────────────────────────────
    let openTodos: [KBTodoItem]          // isDone == false
    
    // ── Routines (per child) ──────────────────────────────────────
    /// Active routines for any child in scope.
    let activeRoutines: [KBRoutine]
    /// Today's completed checks, keyed by routineId.
    let todayChecks: Set<String>
    /// Child name keyed by childId — used to label routines.
    let childNames: [String: String]
    
    // ── Treatments as time-slot constraints ───────────────────────
    /// Active treatments; their `scheduleTimes` are shown as
    /// "busy slots" so the agent knows not to schedule over them.
    let activeTreatments: [KBTreatment]
    
    // ── Health deadlines ─────────────────────────────────────────
    /// Visits that have `nextVisitDate` in the future.
    let visitsWithNextDate: [KBMedicalVisit]
    /// Visits whose `prescribedExams` have a pending deadline.
    let visitsWithPendingExams: [KBMedicalVisit]
    /// Vaccines with status `.scheduled` or `.planned`.
    let upcomingVaccines: [KBVaccine]
    
    // ── Convenience init with sensible defaults ───────────────────
    init(
        familyName:            String,
        memberNames:           [String: String]    = [:],
        horizonDays:           Int                 = 14,
        calendarEvents:        [KBCalendarEvent]   = [],
        openTodos:             [KBTodoItem]        = [],
        activeRoutines:        [KBRoutine]         = [],
        todayChecks:           Set<String>         = [],
        childNames:            [String: String]    = [:],
        activeTreatments:      [KBTreatment]       = [],
        visitsWithNextDate:    [KBMedicalVisit]    = [],
        visitsWithPendingExams:[KBMedicalVisit]    = [],
        upcomingVaccines:      [KBVaccine]         = []
    ) {
        self.familyName             = familyName
        self.memberNames            = memberNames
        self.horizonDays            = min(max(horizonDays, 1), 90)
        self.calendarEvents         = calendarEvents
        self.openTodos              = openTodos
        self.activeRoutines         = activeRoutines
        self.todayChecks            = todayChecks
        self.childNames             = childNames
        self.activeTreatments       = activeTreatments
        self.visitsWithNextDate     = visitsWithNextDate
        self.visitsWithPendingExams = visitsWithPendingExams
        self.upcomingVaccines       = upcomingVaccines
    }
}

// MARK: - Builder

enum PlanningContextBuilder {
    
    // MARK: - Main entry point
    
    static func buildSystemPrompt(input: PlanningContextInput) -> String {
        
        KBLog.ai.kbInfo("""
        PlanningContextBuilder start \
        family=\(input.familyName) \
        horizonDays=\(input.horizonDays) \
        events=\(input.calendarEvents.count) \
        todos=\(input.openTodos.count) \
        routines=\(input.activeRoutines.count) \
        treatments=\(input.activeTreatments.count) \
        nextVisits=\(input.visitsWithNextDate.count) \
        pendingExams=\(input.visitsWithPendingExams.count) \
        vaccines=\(input.upcomingVaccines.count)
        """)
        
        let now      = Date()
        let horizon  = Calendar.current.date(
            byAdding: .day, value: input.horizonDays, to: now
        ) ?? now
        
        var lines: [String] = []
        
        // ── Role + rules ─────────────────────────────────────────────
        lines.append("""
        Sei un assistente di pianificazione familiare integrato nell'app KidBox.
        Hai accesso al calendario, ai to-do, alle routine dei bambini, alle cure \
        attive e alle scadenze sanitarie della famiglia \(input.familyName).
        
        REGOLE IMPORTANTI:
        - Aiuta i genitori a pianificare, trovare spazi liberi e non dimenticare scadenze.
        - Non dare consigli medici vincolanti; per questioni cliniche invita a sentire il medico.
        - Quando proponi di creare un evento o un to-do, specifica sempre titolo, data/ora \
          e (se rilevante) il membro da assegnare.
        - Parla sempre in italiano, con un tono caldo e pratico.
        - L'orizzonte temporale corrente è \(formatDate(now)) — \(formatDate(horizon)) \
          (\(input.horizonDays) giorni).
        """)
        
        // ── Today's snapshot ─────────────────────────────────────────
        appendTodaySnapshot(input: input, now: now, to: &lines)
        
        // ── Calendar events ──────────────────────────────────────────
        appendCalendarEvents(input.calendarEvents, now: now, horizon: horizon, to: &lines)
        
        // ── Open to-do items ─────────────────────────────────────────
        appendTodos(input.openTodos, memberNames: input.memberNames, now: now, horizon: horizon, to: &lines)
        
        // ── Daily routines ───────────────────────────────────────────
        appendRoutines(input.activeRoutines, todayChecks: input.todayChecks, childNames: input.childNames, to: &lines)
        
        // ── Active treatments as time constraints ────────────────────
        appendTreatments(input.activeTreatments, childNames: input.childNames, now: now, to: &lines)
        
        // ── Health deadlines ─────────────────────────────────────────
        appendHealthDeadlines(
            visitsWithNextDate:     input.visitsWithNextDate,
            visitsWithPendingExams: input.visitsWithPendingExams,
            upcomingVaccines:       input.upcomingVaccines,
            now:    now,
            horizon: horizon,
            to:     &lines
        )
        
        lines.append("\n--- FINE CONTESTO PIANIFICAZIONE ---")
        lines.append("""
        \nRispondi alle domande del genitore usando le informazioni sopra.
        Quando identifichi un'azione concreta (creare evento, aggiungere to-do, \
        impostare reminder) descrivila in modo chiaro e proponi di eseguirla.
        """)
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("PlanningContextBuilder done chars=\(prompt.count)")
        return prompt
    }
    
    // MARK: - Today snapshot
    
    private static func appendTodaySnapshot(
        input: PlanningContextInput,
        now:   Date,
        to lines: inout [String]
    ) {
        lines.append("\n--- OGGI (\(formatDateShort(now))) ---")
        
        // Events today
        let todayEvents = input.calendarEvents.filter {
            Calendar.current.isDateInToday($0.startDate) && !$0.isDeleted
        }.sorted { $0.startDate < $1.startDate }
        
        if todayEvents.isEmpty {
            lines.append("Nessun evento in calendario oggi.")
        } else {
            lines.append("Eventi di oggi:")
            for e in todayEvents {
                lines.append("  • \(formatEventLine(e))")
            }
        }
        
        // Urgent / overdue todos
        let urgentTodos = input.openTodos.filter {
            ($0.priorityRaw ?? 0) == 1 ||
            ($0.dueAt.map { $0 <= now } ?? false)
        }
        if !urgentTodos.isEmpty {
            lines.append("To-do urgenti / scaduti:")
            for t in urgentTodos {
                lines.append("  • \(formatTodoLine(t, memberNames: input.memberNames))")
            }
        }
        
        // Routines not yet checked today
        let unchecked = input.activeRoutines.filter { !input.todayChecks.contains($0.id) }
        if !unchecked.isEmpty {
            lines.append("Routine non ancora completate oggi:")
            for r in unchecked {
                let child = input.childNames[r.childId] ?? r.childId
                lines.append("  • \(r.title) (\(child))")
            }
        }
        
        // Dose slots for today
        let doseLines = input.activeTreatments.flatMap { t -> [String] in
            let child = input.childNames[t.childId] ?? t.childId
            return t.scheduleTimes.map { slot in
                "  • \(t.drugName) \(String(format: "%.0f", t.dosageValue)) \(t.dosageUnit) — ore \(slot) (\(child))"
            }
        }
        if !doseLines.isEmpty {
            lines.append("Dosi farmaci da somministrare oggi:")
            lines.append(contentsOf: doseLines)
        }
        
        KBLog.ai.kbDebug("PlanningContextBuilder today snapshot: events=\(todayEvents.count) urgentTodos=\(urgentTodos.count) uncheckedRoutines=\(unchecked.count) doselines=\(doseLines.count)")
    }
    
    // MARK: - Calendar events
    
    private static func appendCalendarEvents(
        _ events: [KBCalendarEvent],
        now:      Date,
        horizon:  Date,
        to lines: inout [String]
    ) {
        let upcoming = events
            .filter { !$0.isDeleted && $0.startDate >= now && $0.startDate <= horizon }
            .sorted { $0.startDate < $1.startDate }
        
        guard !upcoming.isEmpty else {
            lines.append("\n--- CALENDARIO (prossimi giorni) ---")
            lines.append("Nessun evento nei prossimi \(Calendar.current.dateComponents([.day], from: now, to: horizon).day ?? 0) giorni.")
            KBLog.ai.kbDebug("PlanningContextBuilder calendar: no upcoming events")
            return
        }
        
        lines.append("\n--- CALENDARIO (\(upcoming.count) eventi) ---")
        
        // Group by day key for readability
        var grouped: [(day: String, events: [KBCalendarEvent])] = []
        var currentDay = ""
        var currentGroup: [KBCalendarEvent] = []
        
        for event in upcoming {
            let dayKey = formatDateShort(event.startDate)
            if dayKey != currentDay {
                if !currentGroup.isEmpty {
                    grouped.append((day: currentDay, events: currentGroup))
                }
                currentDay   = dayKey
                currentGroup = [event]
            } else {
                currentGroup.append(event)
            }
        }
        if !currentGroup.isEmpty {
            grouped.append((day: currentDay, events: currentGroup))
        }
        
        for group in grouped {
            lines.append("\n\(group.day):")
            for e in group.events {
                lines.append("  • \(formatEventLine(e))")
            }
        }
        
        KBLog.ai.kbDebug("PlanningContextBuilder calendar: upcoming=\(upcoming.count)")
    }
    
    // MARK: - To-do items
    
    private static func appendTodos(
        _ todos:       [KBTodoItem],
        memberNames:   [String: String],
        now:           Date,
        horizon:       Date,
        to lines:      inout [String]
    ) {
        guard !todos.isEmpty else {
            KBLog.ai.kbDebug("PlanningContextBuilder todos: none")
            return
        }
        
        // Split: with due date in window vs undated backlog
        let withDue = todos
            .filter { t in t.dueAt.map { $0 >= now && $0 <= horizon } ?? false }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        
        let overdue = todos
            .filter { t in t.dueAt.map { $0 < now } ?? false }
            .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
        
        let backlog = todos
            .filter { $0.dueAt == nil }
            .sorted { ($0.priorityRaw ?? 0) > ($1.priorityRaw ?? 0) }
        
        lines.append("\n--- TO-DO ---")
        
        if !overdue.isEmpty {
            lines.append("Scaduti (\(overdue.count)):")
            for t in overdue {
                lines.append("  ⚠️ \(formatTodoLine(t, memberNames: memberNames))")
            }
        }
        
        if !withDue.isEmpty {
            lines.append("Con scadenza nei prossimi giorni (\(withDue.count)):")
            for t in withDue {
                lines.append("  • \(formatTodoLine(t, memberNames: memberNames))")
            }
        }
        
        if !backlog.isEmpty {
            let cap = min(backlog.count, 10)
            lines.append("Backlog senza data (prime \(cap) su \(backlog.count)):")
            for t in backlog.prefix(cap) {
                lines.append("  • \(formatTodoLine(t, memberNames: memberNames))")
            }
        }
        
        KBLog.ai.kbDebug("PlanningContextBuilder todos: overdue=\(overdue.count) withDue=\(withDue.count) backlog=\(backlog.count)")
    }
    
    // MARK: - Routines
    
    private static func appendRoutines(
        _ routines:   [KBRoutine],
        todayChecks:  Set<String>,
        childNames:   [String: String],
        to lines:     inout [String]
    ) {
        guard !routines.isEmpty else {
            KBLog.ai.kbDebug("PlanningContextBuilder routines: none")
            return
        }
        
        lines.append("\n--- ROUTINE GIORNALIERE (\(routines.count)) ---")
        
        let grouped = Dictionary(grouping: routines) { $0.childId }
        for (childId, childRoutines) in grouped.sorted(by: { $0.key < $1.key }) {
            let name = childNames[childId] ?? childId
            lines.append("\(name):")
            for r in childRoutines.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let status = todayChecks.contains(r.id) ? "✓" : "○"
                lines.append("  \(status) \(r.title)")
            }
        }
        
        KBLog.ai.kbDebug("PlanningContextBuilder routines: count=\(routines.count)")
    }
    
    // MARK: - Active treatments as time constraints
    
    private static func appendTreatments(
        _ treatments: [KBTreatment],
        childNames:   [String: String],
        now:          Date,
        to lines:     inout [String]
    ) {
        guard !treatments.isEmpty else {
            KBLog.ai.kbDebug("PlanningContextBuilder treatments: none")
            return
        }
        
        lines.append("\n--- CURE ATTIVE (slot orari occupati) ---")
        
        for t in treatments {
            let child = childNames[t.childId] ?? t.childId
            var line = "• \(t.drugName)"
            if let ai = t.activeIngredient, !ai.isEmpty { line += " (\(ai))" }
            line += " — \(String(format: "%.0f", t.dosageValue)) \(t.dosageUnit)"
            line += ", \(t.dailyFrequency)x/giorno"
            line += " — orari: \(t.scheduleTimes.joined(separator: ", "))"
            
            if t.isLongTerm {
                line += " [lungo termine]"
            } else if let end = t.endDate {
                let daysLeft = Calendar.current.dateComponents([.day], from: now, to: end).day ?? 0
                line += " [fine: \(formatDate(end))"
                line += daysLeft <= 2 ? " ⚠️ quasi terminata]" : "]"
            }
            line += " (\(child))"
            lines.append(line)
        }
        
        KBLog.ai.kbDebug("PlanningContextBuilder treatments: count=\(treatments.count)")
    }
    
    // MARK: - Health deadlines
    
    private static func appendHealthDeadlines(
        visitsWithNextDate:     [KBMedicalVisit],
        visitsWithPendingExams: [KBMedicalVisit],
        upcomingVaccines:       [KBVaccine],
        now:                    Date,
        horizon:                Date,
        to lines:               inout [String]
    ) {
        let hasContent = !visitsWithNextDate.isEmpty ||
        !visitsWithPendingExams.isEmpty ||
        !upcomingVaccines.isEmpty
        guard hasContent else {
            KBLog.ai.kbDebug("PlanningContextBuilder health deadlines: none")
            return
        }
        
        lines.append("\n--- SCADENZE SANITARIE ---")
        
        // Next visits programmed by the doctor
        if !visitsWithNextDate.isEmpty {
            lines.append("Visite di controllo programmate:")
            for v in visitsWithNextDate.compactMap({ v -> (KBMedicalVisit, Date)? in
                guard let d = v.nextVisitDate else { return nil }
                return (v, d)
            }).sorted(by: { $0.1 < $1.1 }) {
                let (visit, date) = v
                var line = "  • \(formatDate(date))"
                if let reason = visit.nextVisitReason, !reason.isEmpty {
                    line += " — \(reason)"
                }
                if let doctor = visit.doctorName {
                    line += " (Dr. \(doctor))"
                }
                let isPast = date < now
                let isSoon = date <= horizon
                if isPast       { line += " ⚠️ DATA PASSATA, da riprogrammare" }
                else if isSoon  { line += " 📅 in arrivo" }
                lines.append(line)
            }
        }
        
        // Prescribed exams with pending deadlines
        if !visitsWithPendingExams.isEmpty {
            lines.append("Esami prescritti con scadenza:")
            for visit in visitsWithPendingExams {
                for exam in visit.prescribedExams where exam.deadline != nil {
                    guard let deadline = exam.deadline else { continue }
                    var line = "  • \(exam.name)"
                    if exam.isUrgent { line += " [URGENTE]" }
                    let isOverdue = deadline < now
                    line += " — entro \(formatDate(deadline))"
                    if isOverdue { line += " ⚠️ SCADUTO" }
                    else if deadline <= horizon { line += " 📅 in scadenza presto" }
                    if let prep = exam.preparation, !prep.isEmpty {
                        line += " (preparazione: \(prep))"
                    }
                    lines.append(line)
                }
            }
        }
        
        // Scheduled / planned vaccines
        if !upcomingVaccines.isEmpty {
            lines.append("Vaccini in programma:")
            for v in upcomingVaccines.sorted(by: { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }) {
                var line = "  • \(v.vaccineType.displayName)"
                if let name = v.commercialName, !name.isEmpty { line += " (\(name))" }
                line += " — dose \(v.doseNumber)/\(v.totalDoses)"
                line += " [\(v.status.rawValue)]"
                if let date = v.scheduledDate {
                    line += " — \(formatDate(date))"
                    if date < now { line += " ⚠️ DATA PASSATA" }
                }
                lines.append(line)
            }
        }
        
        KBLog.ai.kbDebug("""
        PlanningContextBuilder health deadlines: \
        nextVisits=\(visitsWithNextDate.count) \
        pendingExams=\(visitsWithPendingExams.count) \
        vaccines=\(upcomingVaccines.count)
        """)
    }
    
    // MARK: - Formatting helpers
    
    private static func formatEventLine(_ event: KBCalendarEvent) -> String {
        var line = "[\(event.category.label)] \(event.title)"
        if event.isAllDay {
            line += " (tutto il giorno)"
        } else {
            line += " — \(formatTime(event.startDate))–\(formatTime(event.endDate))"
        }
        if let loc = event.location, !loc.isEmpty {
            line += " @ \(loc)"
        }
        if event.recurrence != .none {
            line += " [\(event.recurrence.label)]"
        }
        return line
    }
    
    private static func formatTodoLine(_ todo: KBTodoItem, memberNames: [String: String]) -> String {
        var line = todo.title
        if (todo.priorityRaw ?? 0) == 1 { line += " [URGENTE]" }
        if let due = todo.dueAt         { line += " — scadenza: \(formatDateTime(due))" }
        if let uid = todo.assignedTo,
           let name = memberNames[uid]  { line += " → \(name)" }
        return line
    }
    
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "it_IT")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    private static func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }
    
    private static func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    
    private static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "it_IT")
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
