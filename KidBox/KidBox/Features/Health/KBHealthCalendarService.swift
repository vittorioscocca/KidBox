//
//  KBHealthCalendarService.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//

//
//  KBHealthCalendarService.swift
//  KidBox
//
//  Crea un KBCalendarEvent a partire da una visita medica, un esame
//  o un vaccino. Chiamato dopo il salvataggio dell'oggetto sanitario,
//  quando l'utente ha confermato di voler aggiungere l'evento al calendario.
//

import Foundation
import SwiftData
import FirebaseAuth
import SwiftUI
import UIKit

// MARK: - Payload

/// Dati pre-compilati da mostrare nello sheet di conferma prima di salvare.
struct HealthCalendarProposal {
    var title:          String
    var startDate:      Date
    var endDate:        Date
    var isAllDay:       Bool
    var category:       KBEventCategory
    var notes:          String?
    var childName:      String
    // Link bidirezionale con l'oggetto sanitario
    var linkedItemId:   String? = nil   // id di KBMedicalVisit / KBMedicalExam / KBVaccine
    var linkedItemType: String? = nil   // "visit" | "exam" | "vaccine"
}

// MARK: - Service

enum KBHealthCalendarService {
    
    // MARK: - Proposal builders
    
    static func proposalForVisit(
        visitId:   String,
        date:      Date,
        reason:    String,
        doctor:    String?,
        childName: String
    ) -> HealthCalendarProposal {
        let title = reason.isEmpty
        ? "Visita medica — \(childName)"
        : "\(reason) — \(childName)"
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
        var notes: String? = nil
        if let d = doctor, !d.isEmpty { notes = "Dr. \(d)" }
        return HealthCalendarProposal(
            title:          title,
            startDate:      date,
            endDate:        end,
            isAllDay:       false,
            category:       .health,
            notes:          notes,
            childName:      childName,
            linkedItemId:   visitId,
            linkedItemType: "visit"
        )
    }
    
    static func proposalForExam(
        examId:    String,
        deadline:  Date,
        name:      String,
        location:  String?,
        childName: String
    ) -> HealthCalendarProposal {
        let title    = "\(name) — \(childName)"
        let dayStart = Calendar.current.startOfDay(for: deadline)
        let dayEnd   = Calendar.current.date(byAdding: .hour, value: 23, to: dayStart) ?? deadline
        var notes: String? = nil
        if let loc = location, !loc.isEmpty { notes = loc }
        return HealthCalendarProposal(
            title:          title,
            startDate:      dayStart,
            endDate:        dayEnd,
            isAllDay:       true,
            category:       .health,
            notes:          notes,
            childName:      childName,
            linkedItemId:   examId,
            linkedItemType: "exam"
        )
    }
    
    static func proposalForVaccine(
        vaccineId:   String,
        date:        Date,
        vaccineName: String,
        dose:        Int,
        totalDoses:  Int,
        childName:   String
    ) -> HealthCalendarProposal {
        let doseLabel = totalDoses > 1 ? " (dose \(dose)/\(totalDoses))" : ""
        let title = "\(vaccineName)\(doseLabel) — \(childName)"
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
        return HealthCalendarProposal(
            title:          title,
            startDate:      date,
            endDate:        end,
            isAllDay:       false,
            category:       .health,
            notes:          nil,
            childName:      childName,
            linkedItemId:   vaccineId,
            linkedItemType: "vaccine"
        )
    }
    
    // MARK: - Save to calendar
    
    @discardableResult
    static func saveToCalendar(
        proposal:     HealthCalendarProposal,
        familyId:     String,
        childId:      String,
        modelContext: ModelContext
    ) -> KBCalendarEvent {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        let event = KBCalendarEvent(
            familyId:        familyId,
            childId:         childId,
            title:           proposal.title,
            notes:           proposal.notes,
            startDate:       proposal.startDate,
            endDate:         proposal.endDate,
            isAllDay:        proposal.isAllDay,
            category:        proposal.category,
            recurrence:      .none,
            reminderMinutes: 60,
            createdAt:       now,
            updatedAt:       now,
            updatedBy:       uid,
            createdBy:       uid
        )
        event.linkedHealthItemId   = proposal.linkedItemId
        event.linkedHealthItemType = proposal.linkedItemType
        event.syncState = .pendingUpsert
        modelContext.insert(event)
        try? modelContext.save()
        
        SyncCenter.shared.enqueueCalendarUpsert(
            eventId:      event.id,
            familyId:     familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.ai.kbInfo("KBHealthCalendarService: event saved id=\(event.id) linkedItemId=\(proposal.linkedItemId ?? "nil")")
        return event
    }
    
    // MARK: - Delete linked calendar event
    
    /// Cerca e cancella il KBCalendarEvent collegato a un oggetto sanitario.
    /// Da chiamare quando si cancella una visita, esame o vaccino.
    static func deleteLinkedCalendarEvent(
        itemId:       String,
        familyId:     String,
        modelContext: ModelContext
    ) {
        let desc = FetchDescriptor<KBCalendarEvent>(
            predicate: #Predicate<KBCalendarEvent> {
                $0.familyId == familyId &&
                $0.linkedHealthItemId == itemId &&
                $0.isDeleted == false
            }
        )
        guard let events = try? modelContext.fetch(desc), !events.isEmpty else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        for event in events {
            event.isDeleted = true
            event.updatedAt = Date()
            event.updatedBy = uid
            event.syncState = .pendingUpsert
            SyncCenter.shared.enqueueCalendarDelete(
                eventId: event.id, familyId: familyId, modelContext: modelContext
            )
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        KBLog.ai.kbInfo("KBHealthCalendarService: deleted linked events for itemId=\(itemId) count=\(events.count)")
    }
    
    // MARK: - Delete linked health item from calendar
    
    /// Da chiamare quando si cancella un KBCalendarEvent con linkedHealthItemId.
    /// Soft-deletes l'oggetto sanitario collegato.
    static func deleteLinkedHealthItem(
        event:        KBCalendarEvent,
        familyId:     String,
        modelContext: ModelContext
    ) {
        guard let itemId = event.linkedHealthItemId,
              let itemType = event.linkedHealthItemType else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        switch itemType {
        case "visit":
            let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == itemId })
            if let v = try? modelContext.fetch(desc).first, !v.isDeleted {
                v.isDeleted = true; v.updatedAt = now; v.updatedBy = uid
                v.syncState = .pendingUpsert
                try? modelContext.save()
                SyncCenter.shared.enqueueVisitDelete(visitId: itemId, familyId: familyId, modelContext: modelContext)
                SyncCenter.shared.flushGlobal(modelContext: modelContext)
                KBLog.ai.kbInfo("KBHealthCalendarService: deleted linked visit id=\(itemId)")
            }
            
        case "exam":
            let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == itemId })
            if let e = try? modelContext.fetch(desc).first, !e.isDeleted {
                e.isDeleted = true; e.updatedAt = now; e.updatedBy = uid
                e.syncState = .pendingUpsert
                try? modelContext.save()
                SyncCenter.shared.enqueueMedicalExamUpsert(examId: itemId, familyId: familyId, modelContext: modelContext)
                SyncCenter.shared.flushGlobal(modelContext: modelContext)
                KBLog.ai.kbInfo("KBHealthCalendarService: deleted linked exam id=\(itemId)")
            }
            
        case "vaccine":
            let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == itemId })
            if let v = try? modelContext.fetch(desc).first, !v.isDeleted {
                v.isDeleted = true; v.updatedAt = now; v.updatedBy = uid
                v.syncState = .pendingUpsert
                try? modelContext.save()
                SyncCenter.shared.enqueueVaccineUpsert(vaccineId: itemId, familyId: familyId, modelContext: modelContext)
                SyncCenter.shared.flushGlobal(modelContext: modelContext)
                KBLog.ai.kbInfo("KBHealthCalendarService: deleted linked vaccine id=\(itemId)")
            }
            
        default:
            KBLog.ai.kbDebug("KBHealthCalendarService: unknown itemType=\(itemType)")
        }
    }
}

// MARK: - Confirmation Sheet

/// Sheet di conferma da presentare dopo il salvataggio di una visita/esame/vaccino.
struct HealthCalendarConfirmSheet: View {
    
    let proposal:    HealthCalendarProposal
    let familyId:    String
    let childId:     String
    let onConfirmed: () -> Void
    let onSkipped:   () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.dismiss)      private var dismiss
    
    @State private var title:     String
    @State private var startDate: Date
    @State private var isAllDay:  Bool
    
    private let tint = KBTheme.tint
    
    init(
        proposal:    HealthCalendarProposal,
        familyId:    String,
        childId:     String,
        onConfirmed: @escaping () -> Void,
        onSkipped:   @escaping () -> Void
    ) {
        self.proposal    = proposal
        self.familyId    = familyId
        self.childId     = childId
        self.onConfirmed = onConfirmed
        self.onSkipped   = onSkipped
        _title     = State(initialValue: proposal.title)
        _startDate = State(initialValue: proposal.startDate)
        _isAllDay  = State(initialValue: proposal.isAllDay)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // ── Icona ────────────────────────────────────────
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(tint.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                        Text("Aggiungere al calendario?")
                            .font(.headline)
                        Text("Puoi modificare il titolo e la data prima di salvare.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 8)
                    
                    // ── Titolo ───────────────────────────────────────
                    formCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TITOLO")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Titolo evento", text: $title)
                                .font(.body)
                        }
                    }
                    
                    // ── Data ─────────────────────────────────────────
                    formCard {
                        Toggle(isOn: $isAllDay) {
                            Label("Tutto il giorno", systemImage: "sun.max")
                        }
                        .tint(tint)
                        
                        Divider()
                        
                        HStack {
                            Text("Data")
                            Spacer()
                            DatePicker(
                                "",
                                selection: $startDate,
                                displayedComponents: isAllDay ? .date : [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "it_IT"))
                        }
                    }
                    
                    // ── Categoria fissa ───────────────────────────────
                    formCard {
                        HStack {
                            Label("Categoria", systemImage: "cross.case.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Salute")
                                .font(.subheadline)
                                .foregroundStyle(tint)
                        }
                    }
                    
                    // ── Azioni ───────────────────────────────────────
                    VStack(spacing: 12) {
                        Button {
                            var finalProposal = proposal
                            finalProposal.title     = title.trimmingCharacters(in: .whitespaces)
                            finalProposal.startDate = startDate
                            finalProposal.endDate   = isAllDay
                            ? Calendar.current.date(byAdding: .hour, value: 23, to: Calendar.current.startOfDay(for: startDate)) ?? startDate
                            : Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
                            finalProposal.isAllDay  = isAllDay
                            
                            KBHealthCalendarService.saveToCalendar(
                                proposal:     finalProposal,
                                familyId:     familyId,
                                childId:      childId,
                                modelContext: modelContext
                            )
                            onConfirmed()
                            dismiss()
                        } label: {
                            Label("Aggiungi al calendario", systemImage: "calendar.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    Capsule().fill(
                                        title.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? tint.opacity(0.4) : tint
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.horizontal)
                        
                        Button {
                            onSkipped()
                            dismiss()
                        } label: {
                            Text("Non aggiungere")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Nuovo evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Salta") {
                        onSkipped()
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KBTheme.cardBackground(colorScheme))
        )
    }
}
