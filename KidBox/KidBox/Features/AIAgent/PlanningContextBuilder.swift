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
    
    // ── Memoria famiglia ─────────────────────────────────────────
    /// Note della famiglia (max ultime 10, non eliminate).
    let recentNotes: [KBNote]
    /// Spese recenti (ultimi 30 giorni, non eliminate).
    let recentExpenses: [KBExpense]
    /// Nomi categorie spesa keyed by categoryId.
    let expenseCategoryNames: [String: String]
    /// Articoli della lista della spesa non ancora acquistati.
    let pendingGroceryItems: [KBGroceryItem]
    /// Messaggi chat di testo recenti (max ultimi 20, no media).
    let recentChatMessages: [KBChatMessage]
    /// Documenti recenti della famiglia (max ultimi 10, non eliminati).
    let recentDocuments: [KBDocument]
    /// Biglietti Wallet recenti (max ultimi 10, non eliminati).
    let recentWalletTickets: [KBWalletTicket]
    
    // ── Animali / Casa / Garage ───────────────────────────────────
    let pets: [KBPet]
    let petEvents: [KBPetEvent]
    let homeItems: [KBHomeItem]
    /// Scadenze e pagamenti Casa (bollette, tasse, mutuo, affitto, ecc.).
    let housePayments: [KBHousePayment]
    let vehicles: [KBVehicle]
    let vehicleEvents: [KBVehicleEvent]
    /// Allegati Casa / Garage / eventi animali con OCR completato (testo pronto per l'AI).
    let lifeAreaDocuments: [KBDocument]
    
    // ── Profili sanitari figli (pediatria avanzata) ───────────────
    /// Tutti i figli della famiglia — per costruire il profilo avanzato.
    let children: [KBChild]
    /// Profili pediatrici keyed by childId (gruppo sanguigno, allergie...).
    let pediatricProfiles: [String: KBPediatricProfile]
    /// Tutte le visite per tutti i figli (filtrate per childId nel builder).
    let allVisits: [KBMedicalVisit]
    /// Tutti gli esami per tutti i figli.
    let allExams: [KBMedicalExam]
    /// Tutti i vaccini per tutti i figli.
    let allVaccines: [KBVaccine]
    
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
        upcomingVaccines:      [KBVaccine]         = [],
        recentNotes:           [KBNote]            = [],
        recentExpenses:        [KBExpense]         = [],
        expenseCategoryNames:  [String: String]    = [:],
        pendingGroceryItems:   [KBGroceryItem]     = [],
        recentChatMessages:    [KBChatMessage]     = [],
        recentDocuments:       [KBDocument]        = [],
        recentWalletTickets:   [KBWalletTicket]    = [],
        pets:                  [KBPet]             = [],
        petEvents:             [KBPetEvent]        = [],
        homeItems:             [KBHomeItem]        = [],
        housePayments:         [KBHousePayment]    = [],
        vehicles:              [KBVehicle]         = [],
        vehicleEvents:         [KBVehicleEvent]    = [],
        lifeAreaDocuments:     [KBDocument]        = [],
        children:              [KBChild]           = [],
        pediatricProfiles:     [String: KBPediatricProfile] = [:],
        allVisits:             [KBMedicalVisit]    = [],
        allExams:              [KBMedicalExam]     = [],
        allVaccines:           [KBVaccine]         = []
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
        self.recentNotes            = recentNotes
        self.recentExpenses         = recentExpenses
        self.expenseCategoryNames   = expenseCategoryNames
        self.pendingGroceryItems    = pendingGroceryItems
        self.recentChatMessages     = recentChatMessages
        self.recentDocuments        = recentDocuments
        self.recentWalletTickets    = recentWalletTickets
        self.pets                   = pets
        self.petEvents              = petEvents
        self.homeItems              = homeItems
        self.housePayments          = housePayments
        self.vehicles               = vehicles
        self.vehicleEvents          = vehicleEvents
        self.lifeAreaDocuments      = lifeAreaDocuments
        self.children               = children
        self.pediatricProfiles      = pediatricProfiles
        self.allVisits              = allVisits
        self.allExams               = allExams
        self.allVaccines            = allVaccines
    }
    
    /// Copia con `lifeAreaDocuments` sostituiti (es. sintesi settimanale dopo fetch OCR).
    func withLifeAreaDocuments(_ docs: [KBDocument]) -> PlanningContextInput {
        PlanningContextInput(
            familyName:             familyName,
            memberNames:            memberNames,
            horizonDays:            horizonDays,
            calendarEvents:         calendarEvents,
            openTodos:              openTodos,
            activeRoutines:         activeRoutines,
            todayChecks:            todayChecks,
            childNames:             childNames,
            activeTreatments:       activeTreatments,
            visitsWithNextDate:     visitsWithNextDate,
            visitsWithPendingExams: visitsWithPendingExams,
            upcomingVaccines:       upcomingVaccines,
            recentNotes:            recentNotes,
            recentExpenses:         recentExpenses,
            expenseCategoryNames:   expenseCategoryNames,
            pendingGroceryItems:    pendingGroceryItems,
            recentChatMessages:     recentChatMessages,
            recentDocuments:        recentDocuments,
            recentWalletTickets:    recentWalletTickets,
            pets:                   pets,
            petEvents:              petEvents,
            homeItems:              homeItems,
            housePayments:          housePayments,
            vehicles:               vehicles,
            vehicleEvents:          vehicleEvents,
            lifeAreaDocuments:      docs,
            children:               children,
            pediatricProfiles:      pediatricProfiles,
            allVisits:              allVisits,
            allExams:               allExams,
            allVaccines:            allVaccines
        )
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
        vaccines=\(input.upcomingVaccines.count) \
        notes=\(input.recentNotes.count) \
        expenses=\(input.recentExpenses.count) \
        grocery=\(input.pendingGroceryItems.count) \
        chat=\(input.recentChatMessages.count) \
        docs=\(input.recentDocuments.count) \
        wallet=\(input.recentWalletTickets.count) \
        pets=\(input.pets.count) petEvents=\(input.petEvents.count) \
        homeItems=\(input.homeItems.count) housePayments=\(input.housePayments.count) \
        vehicles=\(input.vehicles.count) vehicleEvents=\(input.vehicleEvents.count) \
        lifeAreaDocs=\(input.lifeAreaDocuments.count)
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
        attive, alle visite e agli esami, alle scadenze sanitarie, ai documenti, al wallet, \
        alle note, alle spese, alla lista della spesa, agli ultimi messaggi della chat famiglia, \
        agli animali domestici (con eventi e promemoria), agli oggetti di casa (garanzie, manutenzione, contratti), \
        alle scadenze e pagamenti domestici (bollette, tasse, mutuo, affitto), \
        e al garage (veicoli e interventi) \
        di \(input.familyName).
        
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
        
        // ── Memoria famiglia ─────────────────────────────────────────
        appendNotes(input.recentNotes, memberNames: input.memberNames, to: &lines)
        appendExpenses(input.recentExpenses, categoryNames: input.expenseCategoryNames,
                       memberNames: input.memberNames, to: &lines)
        appendGrocery(input.pendingGroceryItems, to: &lines)
        appendChatMessages(input.recentChatMessages, to: &lines)
        appendDocuments(input.recentDocuments, to: &lines)
        appendWalletTickets(input.recentWalletTickets, to: &lines)
        
        appendPetsHomeGarage(
            pets: input.pets,
            petEvents: input.petEvents,
            homeItems: input.homeItems,
            housePayments: input.housePayments,
            vehicles: input.vehicles,
            vehicleEvents: input.vehicleEvents,
            lifeDocuments: input.lifeAreaDocuments,
            now: now,
            horizon: horizon,
            to: &lines
        )
        
        // ── Profili sanitari figli (pediatria avanzata) ───────────────
        appendChildrenHealthProfiles(input: input, to: &lines)
        
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
    
    // MARK: - Note
    
    private static func appendNotes(
        _ notes:      [KBNote],
        memberNames:  [String: String],
        to lines:     inout [String]
    ) {
        guard !notes.isEmpty else { return }
        let capped = Array(notes.prefix(10))
        lines.append("\n--- NOTE FAMIGLIA (ultime \(capped.count)) ---")
        for n in capped {
            let author = memberNames[n.updatedBy] ?? n.updatedByName
            var line = "• [\(formatDate(n.updatedAt))] \(n.title.isEmpty ? "(senza titolo)" : n.title)"
            if !n.body.isEmpty {
                // Tronca a 200 caratteri per non gonfiare il prompt
                let preview = String(n.body.prefix(200))
                line += ": \(preview)\(n.body.count > 200 ? "…" : "")"
            }
            line += " — \(author)"
            lines.append(line)
        }
        KBLog.ai.kbDebug("PlanningContextBuilder notes appended count=\(capped.count)")
    }
    
    // MARK: - Expenses
    
    private static func appendExpenses(
        _ expenses:     [KBExpense],
        categoryNames:  [String: String],
        memberNames:    [String: String],
        to lines:       inout [String]
    ) {
        guard !expenses.isEmpty else { return }
        let total = expenses.reduce(0.0) { $0 + $1.amount }
        lines.append("\n--- SPESE RECENTI (\(expenses.count) · totale €\(String(format: "%.2f", total))) ---")
        for e in expenses.prefix(15) {
            let cat = e.categoryId.flatMap { categoryNames[$0] } ?? "Altro"
            let who = e.createdByUid.flatMap { memberNames[$0] } ?? ""
            var line = "• \(formatDate(e.date)) — \(e.title) €\(String(format: "%.2f", e.amount)) [\(cat)]"
            if !who.isEmpty { line += " — \(who)" }
            if let notes = e.notes, !notes.isEmpty { line += " (\(notes))" }
            lines.append(line)
        }
        KBLog.ai.kbDebug("PlanningContextBuilder expenses appended count=\(expenses.count) total=\(total)")
    }
    
    // MARK: - Grocery
    
    private static func appendGrocery(
        _ items:  [KBGroceryItem],
        to lines: inout [String]
    ) {
        guard !items.isEmpty else { return }
        lines.append("\n--- LISTA DELLA SPESA (\(items.count) articoli da acquistare) ---")
        // Raggruppa per categoria
        let grouped = Dictionary(grouping: items) { $0.category ?? "Altro" }
        for (cat, catItems) in grouped.sorted(by: { $0.key < $1.key }) {
            let names = catItems.map { $0.name }.joined(separator: ", ")
            lines.append("  [\(cat)] \(names)")
        }
        KBLog.ai.kbDebug("PlanningContextBuilder grocery appended count=\(items.count)")
    }
    
    // MARK: - Chat messages
    
    private static func appendChatMessages(
        _ messages: [KBChatMessage],
        to lines:   inout [String]
    ) {
        // Solo messaggi di testo, no media/posizione
        let textMessages = messages.filter { $0.type == .text && !($0.text?.isEmpty ?? true) }
        guard !textMessages.isEmpty else { return }
        let capped = Array(textMessages.suffix(15)) // ultimi 15
        lines.append("\n--- CHAT FAMIGLIA (ultimi \(capped.count) messaggi di testo) ---")
        for m in capped {
            let text = m.text ?? ""
            let preview = String(text.prefix(150))
            lines.append("  [\(formatDateTime(m.createdAt))] \(m.senderName): \(preview)\(text.count > 150 ? "…" : "")")
        }
        KBLog.ai.kbDebug("PlanningContextBuilder chat appended count=\(capped.count)")
    }
    
    // MARK: - Profili sanitari figli
    
    /// Delega a PediatricAdvancedContextBuilder per ogni figlio.
    /// In questo modo la logica di analisi longitudinale è in un unico posto
    /// e può essere riusata da HealthAIChatViewModel in futuro.
    private static func appendChildrenHealthProfiles(
        input:    PlanningContextInput,
        to lines: inout [String]
    ) {
        guard !input.children.isEmpty else { return }
        lines.append("\n--- PROFILI SANITARI FIGLI ---")
        
        for child in input.children {
            let profile         = input.pediatricProfiles[child.id]
            let childVisits     = input.allVisits.filter     { !$0.isDeleted && $0.childId == child.id }
            let childExams      = input.allExams.filter      { !$0.isDeleted && $0.childId == child.id }
            let childVaccines   = input.allVaccines.filter   { !$0.isDeleted && $0.childId == child.id }
            let childTreatments = input.activeTreatments.filter { !$0.isDeleted && $0.childId == child.id }
            
            let advInput = PediatricAdvancedInput(
                familyId:      child.familyId ?? "",
                subject:       .child(child, profile: profile),
                subjectId:     child.id,
                allVisits:     childVisits,
                allExams:      childExams,
                allTreatments: childTreatments,
                allVaccines:   childVaccines,
                historicDays:  365
            )
            
            // buildSystemPrompt genera un testo completo — lo appendiamo
            // direttamente come blocco nel prompt dell'agente.
            let childPrompt = PediatricAdvancedContextBuilder.buildSystemPrompt(input: advInput)
            lines.append(childPrompt)
        }
        
        KBLog.ai.kbDebug("PlanningContextBuilder childProfiles appended count=\(input.children.count)")
    }
    
    // MARK: - Animali, Casa, Garage
    
    private static func appendPetsHomeGarage(
        pets: [KBPet],
        petEvents: [KBPetEvent],
        homeItems: [KBHomeItem],
        housePayments: [KBHousePayment],
        vehicles: [KBVehicle],
        vehicleEvents: [KBVehicleEvent],
        lifeDocuments: [KBDocument],
        now: Date,
        horizon: Date,
        to lines: inout [String]
    ) {
        let petList = pets.filter { !$0.isDeleted }
        let eventList = petEvents.filter { !$0.isDeleted }
        let homeList = homeItems.filter { !$0.isDeleted }
        let paymentList = housePayments.filter { !$0.isDeleted }
        let vehicleList = vehicles.filter { !$0.isDeleted }
        let vehEventList = vehicleEvents.filter { !$0.isDeleted }
        
        let petPastWindow = Calendar.current.date(byAdding: .day, value: -180, to: now) ?? now
        let vehiclePastWindow = Calendar.current.date(byAdding: .day, value: -365, to: now) ?? now
        let petNames = Dictionary(uniqueKeysWithValues: petList.map { ($0.id, $0.name) })
        
        if !petList.isEmpty {
            lines.append("\n--- ANIMALI (\(petList.count)) ---")
            for p in petList.prefix(20) {
                var line = "• \(p.name) — specie: \(p.species)"
                if let b = p.breed, !b.isEmpty { line += ", razza: \(b)" }
                if let bd = p.birthDate { line += " — nascita: \(formatDate(bd))" }
                if let c = p.color, !c.isEmpty { line += " — colore: \(c)" }
                if let chip = p.chipCode, !chip.isEmpty { line += ", chip: \(chip)" }
                if let n = p.notes, !n.isEmpty {
                    let short = String(n.prefix(120))
                    line += " — note: \(short)\(n.count > 120 ? "…" : "")"
                }
                lines.append(line)
            }
        }
        
        let relevantPetEvents = eventList.filter { ev in
            (ev.date >= petPastWindow && ev.date <= horizon) ||
            (ev.nextDueDate.map { $0 >= now && $0 <= horizon } ?? false)
        }.sorted { $0.date > $1.date }
        
        if !relevantPetEvents.isEmpty {
            lines.append("\n--- EVENTI ANIMALI (finestra utile) ---")
            for ev in relevantPetEvents.prefix(25) {
                let pet = petNames[ev.petId] ?? "animale"
                var line = "• [\(formatDate(ev.date))] \(ev.title) (\(pet)) — tipo: \(ev.eventTypeRaw)"
                if let nd = ev.nextDueDate {
                    line += " — prossimo: \(formatDate(nd))"
                    if nd <= horizon { line += " 📅" }
                }
                if let v = ev.vetName, !v.isEmpty { line += " — vet: \(v)" }
                if let c = ev.cost {
                    line += " — costo: \(KidBoxDecimalFormat.string(from: c)) €"
                }
                if let n = ev.notes, !n.isEmpty {
                    let short = String(n.prefix(80))
                    line += " — note: \(short)\(n.count > 80 ? "…" : "")"
                }
                lines.append(line)
                appendLifeAreaDocExtracts(
                    lifeDocuments: lifeDocuments,
                    matching: { PetEventAttachmentTag.matches($0, eventId: ev.id) },
                    indent: "    ",
                    to: &lines
                )
            }
        }
        
        if !homeList.isEmpty {
            lines.append("\n--- CASA / OGGETTI (\(homeList.count)) ---")
            for h in homeList.prefix(25) {
                var line = "• \(h.name) [\(homeItemCategoryLabel(h.categoryRaw))]"
                let bm = [h.brand, h.model].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
                if !bm.isEmpty { line += " — \(bm)" }
                if let sn = h.serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !sn.isEmpty {
                    line += " — s/n: \(sn)"
                }
                if let pd = h.purchaseDate {
                    line += " — acquisto: \(formatDate(pd))"
                }
                if let w = h.warrantyExpiryDate {
                    line += " — garanzia fino: \(formatDate(w))"
                    if w >= now && w <= horizon { line += " 📅 in scadenza" }
                    if w < now { line += " ⚠️ scaduta" }
                }
                if let s = h.nextServiceDate {
                    line += " — prossima manutenzione: \(formatDate(s))"
                    if s >= now && s <= horizon { line += " 📅" }
                }
                if let m = h.servicePeriodMonths {
                    line += " — periodicità: ogni \(m) mesi"
                }
                if h.reminderEnabled { line += " — promemoria: attivo" }
                if let n = h.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    let short = String(n.prefix(100))
                    line += " — note: \(short)\(n.count > 100 ? "…" : "")"
                }
                lines.append(line)
                appendLifeAreaDocExtracts(
                    lifeDocuments: lifeDocuments,
                    matching: { HomeItemAttachmentTag.matches($0, homeItemId: h.id) },
                    indent: "    ",
                    to: &lines
                )
            }
        }

        if !paymentList.isEmpty {
            lines.append("\n--- CASA / SCADENZE E PAGAMENTI (\(paymentList.count)) ---")
            for p in paymentList.sorted(by: { $0.name < $1.name }).prefix(35) {
                var line = "• \(p.name) — tipo: \(housePaymentTypeLabel(p.typeRaw))"
                if let st = p.subtypeRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty {
                    line += " (\(st))"
                }
                if let imp = p.importo {
                    line += " — importo: \(KidBoxDecimalFormat.string(from: imp)) €"
                }
                if let g = p.giornoDiScadenzaMensile {
                    line += " — giorno scadenza mensile: \(g)"
                }
                if let ds = p.dataScadenza {
                    line += " — scadenza annuale di riferimento: \(formatDate(ds))"
                }
                if let dc = p.dataScadenzaContratto {
                    line += " — scadenza contratto: \(formatDate(dc))"
                    if dc >= now && dc <= horizon { line += " 📅" }
                    if dc < now { line += " ⚠️ passata" }
                }
                if let f = p.fornitore?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
                    line += " — gestore: \(f)"
                }
                if let ed = p.earliestDisplayDeadline(from: now) {
                    line += " — prossima scadenza in agenda: \(formatDate(ed))"
                    if ed >= now && ed <= horizon { line += " 📅" }
                    if ed < now { line += " ⚠️" }
                }
                line += p.reminderOn ? " — promemoria: sì" : " — promemoria: no"
                if let n = p.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    let short = String(n.prefix(100))
                    line += " — note: \(short)\(n.count > 100 ? "…" : "")"
                }
                lines.append(line)
                appendLifeAreaDocExtracts(
                    lifeDocuments: lifeDocuments,
                    matching: { HousePaymentAttachmentTag.matches($0, paymentId: p.id) },
                    indent: "    ",
                    to: &lines
                )
            }
        }
        
        if !vehicleList.isEmpty {
            lines.append("\n--- GARAGE / VEICOLI (\(vehicleList.count)) ---")
            for v in vehicleList.prefix(12) {
                var line = "• \(v.name)"
                if let p = v.licensePlate, !p.isEmpty { line += " — targa \(p)" }
                let bm = [v.brand, v.model].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
                if !bm.isEmpty { line += " — \(bm)" }
                if let y = v.year { line += " — anno \(y)" }
                if let ins = v.insuranceExpiryDate {
                    line += " — assicurazione: \(formatDate(ins))"
                    if ins >= now && ins <= horizon { line += " 📅" }
                }
                if let rev = v.revisionExpiryDate {
                    line += " — revisione: \(formatDate(rev))"
                    if rev >= now && rev <= horizon { line += " 📅" }
                }
                if let tax = v.taxExpiryDate {
                    line += " — bollo: \(formatDate(tax))"
                    if tax >= now && tax <= horizon { line += " 📅" }
                }
                if let ns = v.nextServiceDate {
                    line += " — tagliando/manutenzione: \(formatDate(ns))"
                }
                if let km = v.currentKm { line += " — km attuali: \(km)" }
                if v.reminderEnabled { line += " — promemoria scadenze: attivo" }
                if let n = v.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    let short = String(n.prefix(80))
                    line += " — note: \(short)\(n.count > 80 ? "…" : "")"
                }
                lines.append(line)
                appendLifeAreaDocExtracts(
                    lifeDocuments: lifeDocuments,
                    matching: { VehicleAttachmentTag.matches($0, vehicleId: v.id) },
                    indent: "    ",
                    to: &lines
                )
            }
        }
        
        let vehNames = Dictionary(uniqueKeysWithValues: vehicleList.map { ($0.id, $0.name) })
        let relevantVehEvents = vehEventList.filter { $0.date >= vehiclePastWindow && $0.date <= horizon }
            .sorted { $0.date > $1.date }
        
        if !relevantVehEvents.isEmpty {
            lines.append("\n--- INTERVENTI VEICOLO (ultimo anno + orizzonte) ---")
            for ev in relevantVehEvents.prefix(28) {
                let vn = vehNames[ev.vehicleId] ?? "veicolo"
                var line = "• [\(formatDate(ev.date))] \(ev.title) (\(vn)) — tipo: \(KidBoxVehicleEventType.localized(ev.eventTypeRaw))"
                if let km = ev.km { line += " — \(km) km" }
                if let c = ev.cost {
                    line += " — costo: \(KidBoxDecimalFormat.string(from: c)) €"
                }
                if let g = ev.garageName?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                    line += " — officina: \(g)"
                }
                if let n = ev.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    let short = String(n.prefix(80))
                    line += " — note: \(short)\(n.count > 80 ? "…" : "")"
                }
                lines.append(line)
                appendLifeAreaDocExtracts(
                    lifeDocuments: lifeDocuments,
                    matching: { VehicleEventAttachmentTag.matches($0, eventId: ev.id) },
                    indent: "    ",
                    to: &lines
                )
            }
        }
        
        if petList.isEmpty && relevantPetEvents.isEmpty && homeList.isEmpty && paymentList.isEmpty && vehicleList.isEmpty && relevantVehEvents.isEmpty {
            KBLog.ai.kbDebug("PlanningContextBuilder pets/home/garage: none")
        } else {
            KBLog.ai.kbDebug("""
            PlanningContextBuilder life: pets=\(petList.count) petEvents=\(relevantPetEvents.count) \
            home=\(homeList.count) payments=\(paymentList.count) vehicles=\(vehicleList.count) vehEvents=\(relevantVehEvents.count)
            """)
        }
    }

    private static let planningLifeDocMaxChars = 18_000

    private static func appendLifeAreaDocExtracts(
        lifeDocuments: [KBDocument],
        matching: (KBDocument) -> Bool,
        indent: String,
        to lines: inout [String]
    ) {
        for doc in lifeDocuments where !doc.isDeleted && matching(doc) {
            guard doc.extractionStatus == .completed, doc.hasExtractedText else { continue }
            guard let clipped = clippedPlanningLifeExtract(from: doc) else { continue }
            lines.append("\(indent)Allegato (\(doc.title)) — testo estratto:")
            for row in clipped.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(row)
                if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("\(indent)  \(s)")
                }
            }
        }
    }

    private static func clippedPlanningLifeExtract(from doc: KBDocument) -> String? {
        guard let raw = doc.extractedText else { return nil }
        let sanitized = sanitizePlanningLifeExtractedText(raw)
        guard !sanitized.isEmpty else { return nil }
        if sanitized.count <= planningLifeDocMaxChars { return sanitized }
        let head = String(sanitized.prefix(planningLifeDocMaxChars))
        return head + "\n\n[… Testo troncato per limite contesto AI (\(planningLifeDocMaxChars) caratteri); il file completo è in app. …]"
    }

    private static func sanitizePlanningLifeExtractedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func homeItemCategoryLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "appliance": return "elettrodomestico"
        case "system": return "impianto"
        case "contract": return "contratto"
        case "other": return "altro"
        default: return raw
        }
    }

    private static func housePaymentTypeLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "mutuo": return "mutuo"
        case "affitto": return "affitto"
        case "bolletta": return "bolletta"
        case "tassa": return "tassa"
        case "altro": return "altro"
        default: return raw
        }
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
        f.locale    = kbDeviceLocale()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    private static func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = kbDeviceLocale()
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }
    
    private static func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = kbDeviceLocale()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    
    private static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = kbDeviceLocale()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Documents & Wallet

private extension PlanningContextBuilder {
    static func appendDocuments(_ docs: [KBDocument], to lines: inout [String]) {
        guard !docs.isEmpty else { return }
        lines.append("\n## Documenti (recenti)")
        for d in docs.prefix(10) {
            let scope = d.childId == nil ? "famiglia" : "bambino:\(d.childId!)"
            let extracted = d.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = (extracted?.isEmpty == false)
            lines.append("- \(d.title) (\(scope)) — \(d.fileName) — OCR:\(hasText ? "si" : "no") — aggiornato: \(formatDate(d.updatedAt))")
        }
    }

    static func appendWalletTickets(_ tickets: [KBWalletTicket], to lines: inout [String]) {
        guard !tickets.isEmpty else { return }
        lines.append("\n## Wallet (biglietti recenti)")
        for t in tickets.prefix(10) {
            let whenLine = t.eventDate.map { formatDate($0) } ?? "data: n/d"
            let kind = t.kindRaw
            let emitter = t.emitter?.isEmpty == false ? " — \(t.emitter!)" : ""
            lines.append("- \(t.title) — tipo: \(kind) — \(whenLine)\(emitter)")
        }
    }
}
