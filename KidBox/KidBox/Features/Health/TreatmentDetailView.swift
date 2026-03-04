//
//  TreatmentDetailView.swift
//  KidBox
//
//  Dettaglio cura: progresso, tracking dosi per giorno, orari, estendi, elimina.

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Detail View

struct TreatmentDetailView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @Bindable var treatment: KBTreatment
    
    @Query private var doseLogs: [KBDoseLog]
    @Query private var children: [KBChild]
    
    // Giorno selezionato nella timeline (0-based offset da startDate)
    @State private var selectedDayOffset = 0
    @State private var showExtendSheet   = false
    @State private var showTimeEditor    = false
    @State private var showConfirmDose: ConfirmDoseContext? = nil
    @State private var showDeleteConfirm  = false
    @State private var showStopConfirm    = false
    
    private let tint = Color(red: 0.6, green: 0.45, blue: 0.85)
    
    init(treatment: KBTreatment) {
        self.treatment = treatment
        let tid = treatment.id
        let fid = treatment.familyId
        let cid = treatment.childId
        _doseLogs = Query(filter: #Predicate<KBDoseLog> {
            $0.treatmentId == tid && $0.familyId == fid && $0.childId == cid
        })
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
    }
    
    // MARK: Computed
    
    private var childName: String { children.first?.name ?? "" }
    
    private var totalDays: Int { treatment.isLongTerm ? 30 : treatment.durationDays }
    
    /// Giorni da mostrare nella timeline (max 7 visibili)
    private var timelineDays: [Int] {
        Array(0..<totalDays)
    }
    
    private var dateForOffset: (Int) -> Date {
        { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: treatment.startDate) ?? treatment.startDate
        }
    }
    
    /// Dosi prese in totale
    private var takenCount: Int {
        doseLogs.filter { $0.taken }.count
    }
    
    /// Dosi totali (finite)
    private var totalDoseCount: Int {
        treatment.isLongTerm ? totalDays * treatment.dailyFrequency : treatment.totalDoses
    }
    
    private var progressFraction: Double {
        guard totalDoseCount > 0 else { return 0 }
        return min(Double(takenCount) / Double(totalDoseCount), 1.0)
    }
    
    private var currentDayOffset: Int {
        let cal      = Calendar.current
        let startDay = cal.startOfDay(for: treatment.startDate)
        let today    = cal.startOfDay(for: Date())
        let days     = cal.dateComponents([.day], from: startDay, to: today).day ?? 0
        return max(0, min(days, totalDays - 1))
    }
    
    /// Slot del giorno selezionato
    private var slotsForSelectedDay: [SlotViewModel] {
        let dayNumber = selectedDayOffset + 1
        return treatment.scheduleTimes.enumerated().map { (slotIdx, timeStr) in
            let log = doseLogs.first { $0.dayNumber == dayNumber && $0.slotIndex == slotIdx }
            return SlotViewModel(
                dayNumber: dayNumber,
                slotIndex: slotIdx,
                scheduledTime: timeStr,
                slotLabel: ["Mattina","Pranzo","Sera","Notte"][safe: slotIdx] ?? "Dose \(slotIdx+1)",
                taken:     log?.taken ?? false,
                isSkipped: log != nil && (log?.taken == false),
                takenAt:   log?.takenAt,
                logId:     log?.id
            )
        }
    }
    
    // MARK: Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard
                    .padding()
                
                progressCard
                    .padding(.horizontal)
                
                if !treatment.isLongTerm {
                    extendButton
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                sectionTitle("Orari somministrazione")
                
                timelineRow
                    .padding(.horizontal)
                
                doseSlotsList
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                scheduleInfoCard
                    .padding()
                
                TreatmentAttachmentsSection(treatment: treatment)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                dangerZone
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onAppear { selectedDayOffset = currentDayOffset }
        .sheet(isPresented: $showExtendSheet) {
            ExtendTreatmentSheet(treatment: treatment)
        }
        .sheet(isPresented: $showTimeEditor) {
            EditScheduleTimesSheet(treatment: treatment)
        }
        .sheet(item: $showConfirmDose) { ctx in
            ConfirmDoseSheet(
                treatment: treatment,
                childName: childName,
                context: ctx
            ) { takenAt in
                markDose(context: ctx, takenAt: takenAt)
            }
        }
        .confirmationDialog("Eliminare questa cura?", isPresented: $showDeleteConfirm) {
            Button("Elimina", role: .destructive) { deleteTreatment() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("La cura verrà rimossa da tutti i dispositivi.")
        }
        .confirmationDialog("Interrompere la cura?", isPresented: $showStopConfirm) {
            Button("Interrompi", role: .destructive) { stopTreatment() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("La cura verrà segnata come inattiva. Puoi riattivarla in seguito.")
        }
    }
    
    // MARK: Header
    
    private var headerCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "cross.vial.fill").font(.title).foregroundStyle(tint)
            }
            
            if !childName.isEmpty {
                HStack(spacing: 4) {
                    Text(children.first?.avatarEmoji ?? "👶").font(.caption)
                    Text(childName).font(.caption.bold())
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.1)))
                .foregroundStyle(tint)
            }
            
            HStack(spacing: 6) {
                Text(treatment.drugName).font(.title3.bold())
                Image(systemName: "pencil.circle").foregroundStyle(.secondary).font(.subheadline)
            }
            
            if let ai = treatment.activeIngredient {
                Text(ai).font(.subheadline).foregroundStyle(.secondary)
            }
            
            Text(String(format: "%.0f", treatment.dosageValue) + " \(treatment.dosageUnit)")
                .font(.headline).foregroundStyle(tint)
            
            Text("\(treatment.dailyFrequency) volt\(treatment.dailyFrequency == 1 ? "a" : "e") al giorno")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2))
    }
    
    // MARK: Progress
    
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progresso").font(.subheadline.bold())
            
            HStack(spacing: 16) {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.15), lineWidth: 6)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 56, height: 56)
                        .animation(.easeInOut, value: progressFraction)
                    Text("\(Int(progressFraction * 100))%")
                        .font(.caption.bold()).foregroundStyle(tint)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    let day = currentDayOffset + 1
                    Text("Giorno \(day) di \(totalDays)")
                        .font(.subheadline.bold())
                    if !treatment.isLongTerm {
                        let end = dateForOffset(totalDays - 1)
                        Text("\(treatment.startDate.formatted(.dateTime.day().month(.abbreviated).year())) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(takenCount)/\(totalDoseCount) Dosi totali")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2))
    }
    
    // MARK: Extend button
    
    private var extendButton: some View {
        Button { showExtendSheet = true } label: {
            Label("Estendi cura", systemImage: "calendar.badge.plus")
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.85, green: 0.95, blue: 0.88)))
                .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.4))
                .font(.subheadline.bold())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: Timeline
    
    private var timelineRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timelineDays, id: \.self) { offset in
                        let date    = dateForOffset(offset)
                        let isToday = offset == currentDayOffset
                        let isSelected = offset == selectedDayOffset
                        let dayDoses = doseLogs.filter { $0.dayNumber == offset + 1 }
                        let allTaken = dayDoses.count == treatment.dailyFrequency && dayDoses.allSatisfy { $0.taken }
                        
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.day()))
                                .font(.caption.bold())
                                .foregroundStyle(isSelected ? .white : (isToday ? tint : .primary))
                            Text(date.formatted(.dateTime.month(.abbreviated)))
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                            if allTaken {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(isSelected ? .white : .green)
                            }
                        }
                        .frame(width: 44, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? tint : (isToday ? tint.opacity(0.1) : Color(.systemBackground)))
                        )
                        .onTapGesture { withAnimation { selectedDayOffset = offset } }
                        .id(offset)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo(currentDayOffset, anchor: .center) }
                }
            }
        }
    }
    
    // MARK: Dose slots
    
    private var doseSlotsList: some View {
        VStack(spacing: 10) {
            ForEach(slotsForSelectedDay, id: \.slotIndex) { slot in
                doseSlotRow(slot)
            }
        }
    }
    
    private func doseSlotRow(_ slot: SlotViewModel) -> some View {
        HStack(spacing: 14) {
            // Clock icon
            ZStack {
                Circle()
                    .fill(slot.taken ? tint.opacity(0.1) : slot.isSkipped ? Color.orange.opacity(0.1) : Color(.systemGray6))
                    .frame(width: 40, height: 40)
                Image(systemName: slot.isSkipped ? "xmark" : "clock.fill")
                    .foregroundStyle(slot.taken ? tint : slot.isSkipped ? .orange : .secondary)
                    .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.scheduledTime).font(.subheadline.bold())
                if slot.taken, let at = slot.takenAt {
                    Text("Presa: \(at.formatted(.dateTime.hour().minute()))")
                        .font(.caption).foregroundStyle(.green)
                } else if slot.isSkipped {
                    Label("Saltata", systemImage: "xmark.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Da prendere").font(.caption).foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if slot.taken {
                // Annulla presa
                Button {
                    undoDose(slot: slot)
                } label: {
                    Text("Annulla").font(.caption).foregroundStyle(tint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().stroke(tint.opacity(0.4)))
                }
                .buttonStyle(.plain)
            } else if slot.isSkipped {
                // Riprendi (annulla salto)
                Button {
                    undoDose(slot: slot)
                } label: {
                    Text("Riprendi").font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().stroke(Color.orange.opacity(0.4)))
                }
                .buttonStyle(.plain)
            } else {
                // Salta (X) + Conferma (✓)
                HStack(spacing: 8) {
                    Button {
                        skipDose(slot: slot)
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(.systemGray5)))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showConfirmDose = ConfirmDoseContext(
                            dayNumber: slot.dayNumber,
                            slotIndex: slot.slotIndex,
                            scheduledTime: slot.scheduledTime,
                            drugName: treatment.drugName,
                            dosageValue: treatment.dosageValue,
                            dosageUnit: treatment.dosageUnit
                        )
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.green))
                            .foregroundStyle(.white)
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1))
    }
    
    // MARK: Schedule info
    
    private var scheduleInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Imposta gli orari per \(treatment.dailyFrequency) dosi giornaliere")
                .font(.subheadline).foregroundStyle(.secondary)
            
            let labels = ["Mattina", "Pranzo", "Sera", "Notte"]
            ForEach(treatment.scheduleTimes.indices, id: \.self) { i in
                HStack {
                    Text(labels[safe: i] ?? "Dose \(i+1)").foregroundStyle(.secondary)
                    Spacer()
                    Text(treatment.scheduleTimes[i]).font(.subheadline.bold())
                }
                .font(.subheadline)
            }
            
            Button { showTimeEditor = true } label: {
                Label("Personalizza orari", systemImage: "clock.badge.checkmark")
                    .frame(maxWidth: .infinity).padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.4)))
                    .foregroundStyle(tint).font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2))
    }
    
    // MARK: Danger zone
    
    private var dangerZone: some View {
        VStack(spacing: 10) {
            if treatment.isActive {
                Button { showStopConfirm = true } label: {
                    Label("Interrompi cura", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(Color.orange.opacity(0.08)))
                        .foregroundStyle(.orange).font(.subheadline.bold())
                }
                .buttonStyle(.plain)
            } else {
                Button { reactivateTreatment() } label: {
                    Label("Riattiva cura", systemImage: "play.circle")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.08)))
                        .foregroundStyle(.green).font(.subheadline.bold())
                }
                .buttonStyle(.plain)
            }
            
            Button { showDeleteConfirm = true } label: {
                Label("Elimina", systemImage: "trash")
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.06)))
                    .foregroundStyle(.red).font(.subheadline.bold())
            }
            .buttonStyle(.plain)
        }
    }
    
    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.bold())
            .padding(.horizontal).padding(.top, 16).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: Actions
    
    private func markDose(context ctx: ConfirmDoseContext, takenAt: Date) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        if let existing = doseLogs.first(where: { $0.dayNumber == ctx.dayNumber && $0.slotIndex == ctx.slotIndex }) {
            existing.taken     = true
            existing.takenAt   = takenAt
            existing.updatedAt = now
            existing.updatedBy = uid
            try? modelContext.save()
            SyncCenter.shared.enqueueDoseLogUpsert(
                logId: existing.id,      // ← usa `existing` non `log`
                familyId: treatment.familyId,
                modelContext: modelContext
            )
        } else {
            let newLog = KBDoseLog(
                familyId: treatment.familyId,
                childId:  treatment.childId,
                treatmentId: treatment.id,
                dayNumber: ctx.dayNumber,
                slotIndex: ctx.slotIndex,
                scheduledTime: ctx.scheduledTime,
                takenAt: takenAt,
                taken: true,
                updatedBy: uid
            )
            modelContext.insert(newLog)
            try? modelContext.save()
            SyncCenter.shared.enqueueDoseLogUpsert(
                logId: newLog.id,        // ← usa `newLog`
                familyId: treatment.familyId,
                modelContext: modelContext
            )
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func skipDose(slot: SlotViewModel) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let doseLog: KBDoseLog
        if let existing = doseLogs.first(where: { $0.dayNumber == slot.dayNumber && $0.slotIndex == slot.slotIndex }) {
            existing.taken     = false
            existing.takenAt   = nil
            existing.updatedAt = Date()
            existing.updatedBy = uid
            doseLog = existing
        } else {
            let newLog = KBDoseLog(
                familyId: treatment.familyId, childId: treatment.childId,
                treatmentId: treatment.id,
                dayNumber: slot.dayNumber, slotIndex: slot.slotIndex,
                scheduledTime: slot.scheduledTime,
                takenAt: nil, taken: false, updatedBy: uid
            )
            modelContext.insert(newLog)
            doseLog = newLog
        }
        try? modelContext.save()
        SyncCenter.shared.enqueueDoseLogUpsert(
            logId: doseLog.id,
            familyId: treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func undoDose(slot: SlotViewModel) {
        guard let log = doseLogs.first(where: { $0.dayNumber == slot.dayNumber && $0.slotIndex == slot.slotIndex }) else { return }
        modelContext.delete(log)
        try? modelContext.save()
        
        SyncCenter.shared.enqueueDoseLogDelete(
            logId: log.id,
            familyId: treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func stopTreatment() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.isActive  = false
        treatment.updatedAt = Date()
        treatment.updatedBy = uid
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentUpsert(
            treatmentId: treatment.id,
            familyId: treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
    
    private func reactivateTreatment() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.isActive  = true
        treatment.updatedAt = Date()
        treatment.updatedBy = uid
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentUpsert(
            treatmentId: treatment.id,
            familyId: treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        // Nessun dismiss — rimane nel detail
    }
    
    private func deleteTreatment() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        TreatmentNotificationManager.cancel(treatmentId: treatment.id)
        treatment.isDeleted = true
        treatment.updatedAt = Date()
        treatment.updatedBy = uid
        try? modelContext.save()
        // ← enqueue delete (rimuove anche su Firestore)
        SyncCenter.shared.enqueueTreatmentDelete(
            treatmentId: treatment.id,
            familyId: treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}

// MARK: - Supporting types

struct SlotViewModel {
    let dayNumber:     Int
    let slotIndex:     Int
    let scheduledTime: String
    let slotLabel:     String
    let taken:         Bool
    let isSkipped:     Bool   // log esiste ma taken=false
    let takenAt:       Date?
    let logId:         String?
}

struct ConfirmDoseContext: Identifiable {
    let id = UUID()
    let dayNumber:     Int
    let slotIndex:     Int
    let scheduledTime: String
    let drugName:      String
    let dosageValue:   Double
    let dosageUnit:    String
}

// MARK: - Confirm Dose Sheet

struct ConfirmDoseSheet: View {
    
    let treatment: KBTreatment
    let childName: String
    let context:   ConfirmDoseContext
    let onConfirm: (Date) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate   = Date()
    @State private var selectedOffset: TimeInterval? = nil   // traccia quale rapido è attivo
    
    private let tint  = Color(red: 0.6, green: 0.45, blue: 0.85)
    private let green = Color(red: 0.3, green: 0.7, blue: 0.45)
    
    private let quickOptions: [(String, TimeInterval)] = [
        ("Adesso",    0),
        ("30 min fa", -30 * 60),
        ("1 ora fa",  -60 * 60),
        ("2 ore fa",  -120 * 60)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // ── Header ──
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(tint.opacity(0.1)).frame(width: 56, height: 56)
                            Image(systemName: "pills.fill").font(.title2).foregroundStyle(tint)
                        }
                        Text(context.drugName).font(.title3.bold())
                        Text(String(format: "%.0f", context.dosageValue) + " \(context.dosageUnit)")
                            .font(.subheadline).foregroundStyle(tint)
                        Text("Quando hai dato la medicina?")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    
                    // ── Selezione rapida ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SELEZIONE RAPIDA")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(quickOptions, id: \.0) { label, offset in
                                let isSelected = selectedOffset == offset
                                Button {
                                    selectedOffset = offset
                                    selectedDate   = Date().addingTimeInterval(offset)
                                } label: {
                                    Text(label)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(isSelected ? green.opacity(0.12) : Color(.systemBackground))
                                                .shadow(color: .black.opacity(isSelected ? 0 : 0.06), radius: 4)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isSelected ? green : Color.clear, lineWidth: 1.5)
                                        )
                                        .font(.subheadline.bold())
                                        .foregroundStyle(isSelected ? green : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // ── Data e ora personalizzata ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SELEZIONA DATA E ORA")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        
                        // DatePicker .graphical aggiorna sempre visivamente
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .tint(tint)
                        .onChange(of: selectedDate) { _, _ in
                            // Se l'utente modifica manualmente, deseleziona i rapidi
                            selectedOffset = nil
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 4)
                        )
                    }
                    .padding(.horizontal)
                    
                    // ── Conferma ──
                    Button {
                        onConfirm(selectedDate)
                        dismiss()
                    } label: {
                        Label("Conferma dose", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 14).fill(green))
                            .foregroundStyle(.white)
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Conferma dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Extend Treatment Sheet

struct ExtendTreatmentSheet: View {
    
    @Bindable var treatment: KBTreatment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @State private var customDays = ""
    @State private var showCustom = false
    
    private let tint     = Color(red: 0.6, green: 0.45, blue: 0.85)
    private let presets  = [3, 5, 7, 10]
    private let green    = Color(red: 0.3, green: 0.65, blue: 0.45)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(green.opacity(0.1)).frame(width: 64, height: 64)
                        Image(systemName: "calendar.badge.plus").font(.title).foregroundStyle(green)
                    }
                    Text("Estendi Cura").font(.title3.bold())
                    Text("Di quanti giorni vuoi estendere il trattamento?")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Grid preset
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(presets, id: \.self) { days in
                        Button { extend(by: days) } label: {
                            VStack(spacing: 2) {
                                Text("\(days)").font(.title2.bold())
                                Text("giorni").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.06), radius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        showCustom = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "ellipsis").font(.title2.bold())
                            Text("Altro").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                if showCustom {
                    HStack {
                        TextField("Numero giorni", text: $customDays).keyboardType(.numberPad)
                            .padding(12).background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button("Aggiungi") {
                            if let d = Int(customDays), d > 0 { extend(by: d) }
                        }
                        .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(green))
                        .foregroundStyle(.white).buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Estendi Cura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func extend(by days: Int) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.durationDays += days
        if let end = treatment.endDate {
            treatment.endDate = Calendar.current.date(byAdding: .day, value: days, to: end)
        }
        treatment.updatedAt = Date()
        treatment.updatedBy = uid
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit Schedule Times Sheet

struct EditScheduleTimesSheet: View {
    
    @Bindable var treatment: KBTreatment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @State private var editedTimes: [String] = []
    private let tint  = Color(red: 0.6, green: 0.45, blue: 0.85)
    private let labels = ["Mattina", "Pranzo", "Sera", "Notte"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(tint.opacity(0.1)).frame(width: 52, height: 52)
                        Image(systemName: "clock.badge.checkmark").font(.title2).foregroundStyle(tint)
                    }
                    Text("Personalizza orari")
                        .font(.title3.bold())
                    Text("Imposta gli orari per \(treatment.dailyFrequency) dos\(treatment.dailyFrequency == 1 ? "e" : "i") giornalier\(treatment.dailyFrequency == 1 ? "a" : "e")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 20).padding(.bottom, 12)
                
                // Time pickers
                VStack(spacing: 0) {
                    ForEach(editedTimes.indices, id: \.self) { i in
                        HStack {
                            ZStack {
                                Circle().fill(tint.opacity(0.1)).frame(width: 32, height: 32)
                                Text("\(i+1)").font(.caption.bold()).foregroundStyle(tint)
                            }
                            Text(labels[safe: i] ?? "Dose \(i+1)")
                                .font(.subheadline)
                            Spacer()
                            TimePickerField(timeString: $editedTimes[i])
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        
                        if i < editedTimes.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 6))
                .padding()
                
                Spacer()
                
                // Salva
                Button { saveTimes() } label: {
                    Text("Salva orari")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                        .foregroundStyle(.white).font(.headline)
                }
                .buttonStyle(.plain)
                .padding(.horizontal).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Orari somministrazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
            .onAppear {
                editedTimes = treatment.scheduleTimes.isEmpty
                ? Array(repeating: "08:00", count: treatment.dailyFrequency)
                : treatment.scheduleTimes
            }
        }
        .presentationDetents([.medium])
    }
    
    private func saveTimes() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.scheduleTimes = editedTimes
        treatment.updatedAt     = Date()
        treatment.updatedBy     = uid
        try? modelContext.save()
        
        SyncCenter.shared.enqueueTreatmentUpsert(
            treatmentId: treatment.id,
            familyId: treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        // Rischedula notifiche se attive
        if treatment.reminderEnabled {
            TreatmentNotificationManager.cancel(treatmentId: treatment.id)
            TreatmentNotificationManager.schedule(
                treatment: treatment,
                childName: ""
            )
        }
        dismiss()
    }
}
