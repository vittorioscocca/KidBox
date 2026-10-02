//
//  PlanningContextBuilder.swift
//  KidBox
//
//  Solo l'input dei servizi proattivi (briefing mattutino, recap settimanale).
//  Il contesto dell'assistente non passa più da qui: dal 02/10/2026 lo
//  costruisce il quaderno di schede (`AgentMemoryBook.swift`), vedi
//  `internal/assistente-unico.md`.
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

    /// Fatti narrativi appresi dalle conversazioni precedenti (testo già fetchato).
    let familyMemoryFacts: [String]

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
        allVaccines:           [KBVaccine]         = [],
        familyMemoryFacts:     [String]            = []
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
        self.familyMemoryFacts      = familyMemoryFacts
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
            allVaccines:            allVaccines,
            familyMemoryFacts:      familyMemoryFacts
        )
    }
}
