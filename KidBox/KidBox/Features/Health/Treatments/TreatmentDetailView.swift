//
//  TreatmentDetailView.swift
//  KidBox
//
//  Dettaglio cura: progresso, tracking dosi per giorno, orari, estendi, elimina.
//  Restyled: dynamic light/dark theme matching LoginView.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UserNotifications

// MARK: - Detail View

struct TreatmentDetailView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @Bindable var treatment: KBTreatment
    
    @Query private var doseLogs: [KBDoseLog]
    @Query private var children: [KBChild]
    
    @State private var selectedDayOffset  = 0
    @State private var showEditSheet      = false
    @State private var showExtendSheet    = false
    @State private var showTimeEditor     = false
    @State private var showConfirmDose: ConfirmDoseContext? = nil
    @State private var showDeleteConfirm  = false
    @State private var showStopConfirm    = false
    @State private var notifGranted       = false
    
    private let tint  = KBTheme.tint
    private let green = KBTheme.green
    
    /// Mese abbreviato in italiano (come Android), indipendentemente dalla lingua di sistema.
    private static let timelineMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()
    
    init(treatment: KBTreatment) {
        self.treatment = treatment
        let tid = treatment.id
        let fid = treatment.familyId
        let cid = treatment.childId
        _doseLogs = Query(filter: #Predicate<KBDoseLog> {
            $0.treatmentId == tid && $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
    }
    
    // MARK: Computed

    private var subjectDisplayName: String {
        if treatment.petId.isEmpty {
            return children.first?.name ?? ""
        }
        let pid = treatment.petId
        let d = FetchDescriptor<KBPet>(predicate: #Predicate<KBPet> { $0.id == pid })
        return (try? modelContext.fetch(d).first?.name) ?? "Animale domestico"
    }
    private var totalDays: Int {
        guard treatment.isLongTerm else { return treatment.durationDays }
        let cal = Calendar.current
        let start = cal.startOfDay(for: treatment.startDate)
        let today = cal.startOfDay(for: Date())
        let daysSinceStart = cal.dateComponents([.day], from: start, to: today).day ?? 0
        return max(daysSinceStart + 7, 7)   // almeno 7 giorni futuri visibili
    }
    private var timelineDays: [Int] { Array(0..<totalDays) }
    
    private var dateForOffset: (Int) -> Date {
        { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: treatment.startDate) ?? treatment.startDate
        }
    }
    
    private var takenCount: Int { doseLogs.filter { $0.taken }.count }
    
    private var totalDoseCount: Int {
        if !treatment.isLongTerm { return treatment.totalDoses }
        if treatment.usesIntervalSchedule {
            let n = treatment.intervalBetweenDosesDays
            guard n > 0 else { return totalDays * treatment.dailyFrequency }
            return (0..<totalDays).filter { treatment.isScheduledDoseDay(calendarDayOffsetFromStart: $0) }.count
        }
        return totalDays * treatment.dailyFrequency
    }
    
    /// Numero di dosi previste nel giorno di calendario `dayOffset` (0 = primo giorno cura).
    private func expectedDoseSlotsCount(dayOffset: Int) -> Int {
        if treatment.usesIntervalSchedule {
            return treatment.isScheduledDoseDay(calendarDayOffsetFromStart: dayOffset) ? 1 : 0
        }
        return treatment.dailyFrequency
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
        if treatment.isLongTerm { return max(0, days) }
        return max(0, min(days, totalDays - 1))
    }
    
    /// Giorno della timeline (offset da inizio cura) con data di calendario successiva a oggi.
    private func isFutureDayOffset(_ offset: Int) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: dateForOffset(offset))
        let todayStart = cal.startOfDay(for: Date())
        return dayStart > todayStart
    }
    
    private var isSelectedDayFuture: Bool { isFutureDayOffset(selectedDayOffset) }
    
    private var slotsForSelectedDay: [SlotViewModel] {
        let dayNumber = selectedDayOffset + 1
        let times = treatment.scheduleTimes
        if treatment.usesIntervalSchedule {
            guard treatment.isScheduledDoseDay(calendarDayOffsetFromStart: selectedDayOffset) else { return [] }
            let slotIdx = 0
            let timeStr = times.first ?? "08:00"
            let log = doseLogs.first { $0.dayNumber == dayNumber && $0.slotIndex == slotIdx && !$0.isDeleted }
            let sched = schedulePeriodForTime(timeStr, slotIndexFallback: slotIdx)
            let label = schedulePeriodLabel(timeStr, slotIndexFallback: slotIdx)
            let chipPeriod: TreatmentSchedulePeriod? = {
                if log?.taken == true, let at = log?.takenAt {
                    return TreatmentSchedulePeriod.from(date: at)
                }
                return sched
            }()
            return [
                SlotViewModel(
                    dayNumber: dayNumber,
                    slotIndex: slotIdx,
                    scheduledTime: timeStr,
                    periodLabel: label,
                    periodForChip: chipPeriod,
                    taken: log?.taken ?? false,
                    isSkipped: log != nil && (log?.taken == false),
                    takenAt: log?.takenAt,
                    logId: log?.id
                )
            ]
        }
        return TreatmentSchedulePeriod.sortedSlotIndices(times: times).map { slotIdx in
            let timeStr = times[slotIdx]
            let log = doseLogs.first { $0.dayNumber == dayNumber && $0.slotIndex == slotIdx && !$0.isDeleted }
            let sched = schedulePeriodForTime(timeStr, slotIndexFallback: slotIdx)
            let label = schedulePeriodLabel(timeStr, slotIndexFallback: slotIdx)
            let chipPeriod: TreatmentSchedulePeriod? = {
                if log?.taken == true, let at = log?.takenAt {
                    return TreatmentSchedulePeriod.from(date: at)
                }
                return sched
            }()
            return SlotViewModel(
                dayNumber: dayNumber,
                slotIndex: slotIdx,
                scheduledTime: timeStr,
                periodLabel: label,
                periodForChip: chipPeriod,
                taken: log?.taken ?? false,
                isSkipped: log != nil && (log?.taken == false),
                takenAt: log?.takenAt,
                logId: log?.id
            )
        }
    }
    
    // MARK: Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard.padding()
                progressCard.padding(.horizontal)
                
                if !treatment.isLongTerm {
                    extendButton.padding(.horizontal).padding(.top, 8)
                }
                
                sectionTitle("Orari somministrazione")
                timelineRow.padding(.horizontal)
                doseSlotsList.padding(.horizontal).padding(.top, 8)
                scheduleInfoCard.padding()
                notesCard.padding(.horizontal).padding(.bottom, 4)
                reminderCard.padding(.horizontal).padding(.bottom, 8)
                if treatment.prescribingVisitId != nil {
                    treatmentPrescribingVisitCard.padding(.horizontal).padding(.bottom, 8)
                }
                TreatmentAttachmentsSection(treatment: treatment).padding(.horizontal).padding(.bottom, 8)
                dangerZone.padding(.horizontal).padding(.top, 8).padding(.bottom, 40)
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Cura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .onAppear {
            selectedDayOffset = currentDayOffset
            print("🔍 onAppear selectedDayOffset=\(selectedDayOffset) currentDayOffset=\(currentDayOffset)")
            print("🔍 doseLogs count=\(doseLogs.count)")
            for log in doseLogs {
                print("🔍 log dayNumber=\(log.dayNumber) slotIndex=\(log.slotIndex) taken=\(log.taken)")
            }
            Task {
                let s = await UNUserNotificationCenter.current().notificationSettings()
                notifGranted = s.authorizationStatus == .authorized
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .treatmentDoseQuickAction)
        ) { notification in
            guard
                let info = notification.userInfo,
                let tid  = info[TreatmentDoseQuickActionKey.treatmentId] as? String,
                tid == treatment.id
            else { return }
            let day = (info[TreatmentDoseQuickActionKey.dayOffset] as? NSNumber)?.intValue ?? selectedDayOffset
            selectedDayOffset = day
        }
        .sheet(isPresented: $showEditSheet) {
            PediatricTreatmentEditView(
                familyId:  treatment.familyId,
                childId:   treatment.childId,
                childName: subjectDisplayName,
                treatmentId: treatment.id
            )
        }
        .sheet(isPresented: $showExtendSheet) { ExtendTreatmentSheet(treatment: treatment) }
        .sheet(isPresented: $showTimeEditor)  { EditScheduleTimesSheet(treatment: treatment) }
        .sheet(item: $showConfirmDose) { ctx in
            ConfirmDoseSheet(treatment: treatment, childName: subjectDisplayName, context: ctx) { takenAt in
                markDose(context: ctx, takenAt: takenAt)
            }
        }
        .confirmationDialog("Eliminare questa cura?", isPresented: $showDeleteConfirm) {
            Button("Elimina", role: .destructive) { deleteTreatment() }
            Button("Annulla", role: .cancel) { }
        } message: { Text("La cura verrà rimossa da tutti i dispositivi.") }
            .confirmationDialog("Interrompere la cura?", isPresented: $showStopConfirm) {
                Button("Interrompi", role: .destructive) { stopTreatment() }
                Button("Annulla", role: .cancel) { }
            } message: { Text("La cura verrà segnata come inattiva. Puoi riattivarla in seguito.") }
    }
    
    // MARK: - Header
    
    private var headerCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "cross.vial.fill").font(.title).foregroundStyle(tint)
            }
            
            if !subjectDisplayName.isEmpty {
                HStack(spacing: 4) {
                    Text(treatment.petId.isEmpty ? (children.first?.avatarEmoji ?? "👶") : "🐾").font(.caption)
                    Text(subjectDisplayName).font(.caption.bold())
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
            
            Text(treatment.frequencyDisplayLabel)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Progress
    
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progresso").font(.subheadline.bold())
            
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 6).frame(width: 56, height: 56)
                    if treatment.isLongTerm {
                        Image(systemName: "infinity")
                            .font(.title3.bold()).foregroundStyle(tint)
                    } else {
                        Circle()
                            .trim(from: 0, to: progressFraction)
                            .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 56, height: 56)
                            .animation(.easeInOut, value: progressFraction)
                        Text("\(Int(progressFraction * 100))%")
                            .font(.caption.bold()).foregroundStyle(tint)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if treatment.isLongTerm {
                        HStack(spacing: 6) {
                            Image(systemName: "infinity").foregroundStyle(tint).font(.caption.bold())
                            Text("Cura a lungo termine").font(.subheadline.bold())
                        }
                        Text("In corso dal \(localizedDayMonthYear(treatment.startDate))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(takenCount) dosi somministrate").font(.caption).foregroundStyle(.secondary)
                    } else {
                        let day = currentDayOffset + 1
                        Text("Giorno \(day) di \(totalDays)").font(.subheadline.bold())
                        let end = dateForOffset(totalDays - 1)
                        Text("\(localizedDayMonthYear(treatment.startDate)) – \(localizedDayMonthYear(end))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(takenCount)/\(totalDoseCount) Dosi totali")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Extend button
    
    private var extendButton: some View {
        Button { showExtendSheet = true } label: {
            Label("Estendi cura", systemImage: "calendar.badge.plus")
                .frame(maxWidth: .infinity).padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(green.opacity(colorScheme == .dark ? 0.15 : 0.10))
                )
                .foregroundStyle(green).font(.subheadline.bold())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Timeline
    
    private var timelineRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timelineDays, id: \.self) { offset in
                        let date       = dateForOffset(offset)
                        let isToday    = offset == currentDayOffset
                        let isSelected = offset == selectedDayOffset
                        let dayDoses   = doseLogs.filter { $0.dayNumber == offset + 1 && !$0.isDeleted }
                        let expected   = expectedDoseSlotsCount(dayOffset: offset)
                        let allTaken   = expected > 0 && dayDoses.count == expected && dayDoses.allSatisfy { $0.taken }
                        
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.day()))
                                .font(.caption.bold())
                                .foregroundStyle(isSelected ? .white : (isToday ? tint : .primary))
                            Text(Self.timelineMonthFormatter.string(from: date))
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                            if allTaken {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(isSelected ? .white : .green)
                            }
                        }
                        .frame(width: 44, height: 52)
                        .opacity(isFutureDayOffset(offset) ? 0.7 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? tint : (isToday ? tint.opacity(0.1) : KBTheme.cardBackground(colorScheme)))
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
    
    // MARK: - Dose slots
    
    private var doseSlotsList: some View {
        VStack(spacing: 10) {
            if slotsForSelectedDay.isEmpty {
                Text("Nessuna dose programmata per questo giorno.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(KBTheme.cardBackground(colorScheme))
                    )
            } else {
                ForEach(slotsForSelectedDay, id: \.slotIndex) { slot in doseSlotRow(slot) }
            }
        }
    }
    
    private func doseSlotRow(_ slot: SlotViewModel) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(slot.taken ? tint.opacity(0.1) : slot.isSkipped ? Color.orange.opacity(0.1) : KBTheme.inputBackground(colorScheme))
                    .frame(width: 40, height: 40)
                Image(systemName: slot.isSkipped ? "xmark" : "clock.fill")
                    .foregroundStyle(slot.taken ? tint : slot.isSkipped ? .orange : .secondary)
                    .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let p = slot.periodForChip {
                        TreatmentPeriodBadge(period: p)
                    } else {
                        NeutralPeriodBadge(text: slot.periodLabel)
                    }
                    Text(slot.scheduledTime).font(.subheadline.bold())
                }
                if slot.taken, let at = slot.takenAt {
                    Text("Presa: \(localizedHourMinute(at))")
                        .font(.caption).foregroundStyle(.green)
                } else if slot.isSkipped {
                    Label("Saltata", systemImage: "xmark.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if isSelectedDayFuture {
                    Text("Giorno futuro: non puoi registrare assunzioni.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Da prendere").font(.caption).foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if slot.taken {
                Button { undoDose(slot: slot) } label: {
                    Text("Annulla").font(.caption).foregroundStyle(tint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().stroke(tint.opacity(0.4)))
                }
                .buttonStyle(.plain)
            } else if slot.isSkipped {
                Button { undoDose(slot: slot) } label: {
                    Text("Riprendi").font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().stroke(Color.orange.opacity(0.4)))
                }
                .buttonStyle(.plain)
            } else if isSelectedDayFuture {
                EmptyView()
            } else {
                HStack(spacing: 8) {
                    Button { skipDose(slot: slot) } label: {
                        Image(systemName: "xmark")
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(KBTheme.inputBackground(colorScheme)))
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
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 4, x: 0, y: 1)
        )
    }
    
    // MARK: - Schedule info
    
    private var scheduleInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                treatment.usesIntervalSchedule
                ? "Orario nel giorno di assunzione (ogni \(treatment.intervalBetweenDosesDays) giorni)."
                : "Imposta gli orari per \(treatment.dailyFrequency) dosi giornaliere"
            )
                .font(.subheadline).foregroundStyle(.secondary)
            
            let times = treatment.scheduleTimes
            let indices: [Int] = treatment.usesIntervalSchedule
                ? [0]
                : TreatmentSchedulePeriod.sortedSlotIndices(times: times)
            ForEach(indices, id: \.self) { i in
                let time = times.indices.contains(i) ? times[i] : "08:00"
                HStack(spacing: 8) {
                    if let p = schedulePeriodForTime(time, slotIndexFallback: i) {
                        TreatmentPeriodBadge(period: p)
                    } else {
                        NeutralPeriodBadge(text: schedulePeriodLabel(time, slotIndexFallback: i))
                    }
                    Spacer()
                    Text(time).font(.subheadline.bold())
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Notes card
    
    @ViewBuilder
    private var notesCard: some View {
        if let notes = treatment.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Note", systemImage: "square.and.pencil")
                    .font(.subheadline.bold()).foregroundStyle(tint)
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
            )
        }
    }
    
    // MARK: - Reminder card
    
    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Promemoria", systemImage: "bell.fill")
                .font(.subheadline.bold()).foregroundStyle(tint)
            
            if !notifGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifiche disabilitate").font(.caption.bold())
                        Text("Abilita le notifiche nelle Impostazioni per ricevere i promemoria.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
                
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption).foregroundStyle(tint)
                
            } else {
                Toggle(isOn: Binding(
                    get: { treatment.reminderEnabled },
                    set: { newValue in toggleReminder(newValue) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Promemoria attivo")
                        Text(treatment.usesIntervalSchedule ? "Notifica nei giorni di dose, all’orario impostato" : "Notifica per ogni dose agli orari impostati")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                .tint(tint)
                
                if treatment.reminderEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifiche schedulate per:").font(.caption).foregroundStyle(.secondary)
                        let times = treatment.scheduleTimes
                        let idxList: [Int] = treatment.usesIntervalSchedule
                            ? [0]
                            : TreatmentSchedulePeriod.sortedSlotIndices(times: times)
                        ForEach(idxList, id: \.self) { idx in
                            let t = times[idx]
                            HStack(spacing: 6) {
                                Image(systemName: "bell.fill").font(.caption2).foregroundStyle(tint)
                                if let p = schedulePeriodForTime(t, slotIndexFallback: idx) {
                                    TreatmentPeriodBadge(period: p)
                                } else {
                                    NeutralPeriodBadge(text: schedulePeriodLabel(t, slotIndexFallback: idx))
                                }
                                Text(t).font(.caption.bold())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Visita prescrittrice
    
    @ViewBuilder
    private var treatmentPrescribingVisitCard: some View {
        if let vid = treatment.prescribingVisitId {
            TreatmentPrescribingVisitNavRow(
                visitId: vid,
                familyId: treatment.familyId,
                childId: treatment.childId,
                tint: tint,
                colorScheme: colorScheme,
            )
        }
    }
    
    // MARK: - Danger zone
    
    private var dangerZone: some View {
        VStack(spacing: 10) {
            if treatment.isActive {
                Button { showStopConfirm = true } label: {
                    Label("Interrompi cura", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08)))
                        .foregroundStyle(.orange).font(.subheadline.bold())
                }
                .buttonStyle(.plain)
            } else {
                Button { reactivateTreatment() } label: {
                    Label("Riattiva cura", systemImage: "play.circle")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(colorScheme == .dark ? 0.15 : 0.08)))
                        .foregroundStyle(.green).font(.subheadline.bold())
                }
                .buttonStyle(.plain)
            }
            
            Button { showDeleteConfirm = true } label: {
                Label("Elimina", systemImage: "trash")
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(colorScheme == .dark ? 0.15 : 0.06)))
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
    
    // MARK: - Actions
    
    private func toggleReminder(_ enabled: Bool) {
        treatment.reminderEnabled = enabled
        try? modelContext.save()
        if enabled {
            Task {
                let granted = await TreatmentNotificationManager.requestAuthorization()
                if granted {
                    TreatmentNotificationManager.schedule(treatment: treatment, childName: subjectDisplayName)
                } else {
                    await MainActor.run {
                        treatment.reminderEnabled = false
                        try? modelContext.save()
                        notifGranted = false
                    }
                }
            }
        } else {
            TreatmentNotificationManager.cancel(treatmentId: treatment.id)
        }
    }
    
    private func markDose(context ctx: ConfirmDoseContext, takenAt: Date) {
        guard !isFutureDayOffset(ctx.dayNumber - 1) else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let stable = KBDoseLog.stableDocumentId(treatmentId: treatment.id, dayNumber: ctx.dayNumber, slotIndex: ctx.slotIndex)
        let sameSlot = doseLogs.filter {
            $0.treatmentId == treatment.id && $0.dayNumber == ctx.dayNumber && $0.slotIndex == ctx.slotIndex
        }
        let stableRow = sameSlot.first { $0.id == stable }
        for log in sameSlot where log.id != stable {
            SyncCenter.shared.enqueueDoseLogDelete(logId: log.id, familyId: treatment.familyId, modelContext: modelContext)
            modelContext.delete(log)
        }
        if let row = stableRow {
            row.taken = true
            row.takenAt = takenAt
            row.updatedAt = now
            row.updatedBy = uid
            try? modelContext.save()
            SyncCenter.shared.enqueueDoseLogUpsert(logId: stable, familyId: treatment.familyId, modelContext: modelContext)
        } else {
            let newLog = KBDoseLog(
                id: stable,
                familyId: treatment.familyId, childId: treatment.childId,
                treatmentId: treatment.id,
                dayNumber: ctx.dayNumber, slotIndex: ctx.slotIndex,
                scheduledTime: ctx.scheduledTime,
                takenAt: takenAt, taken: true, updatedBy: uid
            )
            modelContext.insert(newLog)
            try? modelContext.save()
            SyncCenter.shared.enqueueDoseLogUpsert(logId: stable, familyId: treatment.familyId, modelContext: modelContext)
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        // Cancella la notifica pendente (e quella già consegnata) per questo slot.
        // Gestisce il caso in cui la dose viene registrata prima dell'orario programmato.
        let dayOffset = ctx.dayNumber - 1
        TreatmentNotificationManager.cancelSlot(
            treatmentId: treatment.id,
            dayOffset:   dayOffset,
            slotIndex:   ctx.slotIndex
        )
    }
    
    private func skipDose(slot: SlotViewModel) {
        guard !isFutureDayOffset(slot.dayNumber - 1) else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let stable = KBDoseLog.stableDocumentId(treatmentId: treatment.id, dayNumber: slot.dayNumber, slotIndex: slot.slotIndex)
        let sameSlot = doseLogs.filter {
            $0.treatmentId == treatment.id && $0.dayNumber == slot.dayNumber && $0.slotIndex == slot.slotIndex
        }
        let stableRow = sameSlot.first { $0.id == stable }
        for log in sameSlot where log.id != stable {
            SyncCenter.shared.enqueueDoseLogDelete(logId: log.id, familyId: treatment.familyId, modelContext: modelContext)
            modelContext.delete(log)
        }
        if let row = stableRow {
            row.taken = false
            row.takenAt = nil
            row.updatedAt = now
            row.updatedBy = uid
        } else {
            let newLog = KBDoseLog(
                id: stable,
                familyId: treatment.familyId, childId: treatment.childId,
                treatmentId: treatment.id,
                dayNumber: slot.dayNumber, slotIndex: slot.slotIndex,
                scheduledTime: slot.scheduledTime,
                takenAt: nil, taken: false, updatedBy: uid
            )
            modelContext.insert(newLog)
        }
        try? modelContext.save()
        SyncCenter.shared.enqueueDoseLogUpsert(logId: stable, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func undoDose(slot: SlotViewModel) {
        let sameSlot = doseLogs.filter {
            $0.treatmentId == treatment.id && $0.dayNumber == slot.dayNumber && $0.slotIndex == slot.slotIndex
        }
        guard !sameSlot.isEmpty else { return }
        for log in sameSlot {
            SyncCenter.shared.enqueueDoseLogDelete(logId: log.id, familyId: treatment.familyId, modelContext: modelContext)
            modelContext.delete(log)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func stopTreatment() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.isActive = false; treatment.updatedAt = Date(); treatment.updatedBy = uid
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentUpsert(treatmentId: treatment.id, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
    
    private func reactivateTreatment() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.isActive = true; treatment.updatedAt = Date(); treatment.updatedBy = uid
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentUpsert(treatmentId: treatment.id, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func deleteTreatment() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        TreatmentNotificationManager.cancel(treatmentId: treatment.id)
        treatment.isDeleted = true; treatment.updatedAt = Date(); treatment.updatedBy = uid
        treatment.syncState = .pendingUpsert; treatment.lastSyncError = nil
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentDelete(treatmentId: treatment.id, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}

// MARK: - Supporting types

struct SlotViewModel {
    let dayNumber: Int
    let slotIndex: Int
    let scheduledTime: String
    /// Etichetta fascia (anche "Dose 5" se non deducibile).
    let periodLabel: String
    /// Fascia per chip colore; se assunta deriva da [takenAt].
    let periodForChip: TreatmentSchedulePeriod?
    let taken: Bool
    let isSkipped: Bool
    let takenAt: Date?
    let logId: String?
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

private enum ConfirmDoseItalianFormatters {
    static let preview: DateFormatter = {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.setLocalizedDateFormatFromTemplate("dMMMMyHHmm")
        return f
    }()
}

// MARK: - Confirm Dose Sheet

struct ConfirmDoseSheet: View {
    
    let treatment: KBTreatment
    let childName: String
    let context:   ConfirmDoseContext
    let onConfirm: (Date) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate   = Date()
    @State private var selectedOffset: TimeInterval? = nil
    @State private var showDatePickerSheet = false
    @State private var showTimePickerSheet = false
    
    private let tint  = KBTheme.tint
    private let green = KBTheme.green
    
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
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(tint.opacity(0.1)).frame(width: 56, height: 56)
                            Image(systemName: "pills.fill").font(.title2).foregroundStyle(tint)
                        }
                        Text(context.drugName).font(.title3.bold())
                        Text(String(format: "%.0f", context.dosageValue) + " \(context.dosageUnit)")
                            .font(.subheadline).foregroundStyle(tint)
                        Text("Orario programmato: \(context.scheduledTime)")
                            .font(.caption).foregroundStyle(.secondary)
                        TreatmentPeriodBadge(period: TreatmentSchedulePeriod.from(date: selectedDate))
                            .padding(.top, 2)
                        Text("Quando hai dato la medicina?")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SELEZIONE RAPIDA").font(.caption.bold()).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(quickOptions, id: \.0) { label, offset in
                                let isSelected = selectedOffset == offset
                                Button {
                                    selectedOffset = offset
                                    selectedDate   = Date().addingTimeInterval(offset)
                                } label: {
                                    Text(label)
                                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(isSelected ? green.opacity(0.12) : KBTheme.cardBackground(colorScheme))
                                                .shadow(color: KBTheme.shadow(colorScheme).opacity(isSelected ? 0 : 1), radius: 4)
                                        )
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? green : Color.clear, lineWidth: 1.5))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(isSelected ? green : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DATA E ORA").font(.caption.bold()).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button {
                                selectedOffset = nil
                                showDatePickerSheet = true
                            } label: {
                                Text("Data")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(KBTheme.cardBackground(colorScheme))
                                            .shadow(color: KBTheme.shadow(colorScheme), radius: 4)
                                    )
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                selectedOffset = nil
                                showTimePickerSheet = true
                            } label: {
                                Text("Ora")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(KBTheme.cardBackground(colorScheme))
                                            .shadow(color: KBTheme.shadow(colorScheme), radius: 4)
                                    )
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Text(ConfirmDoseItalianFormatters.preview.string(from: selectedDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Button {
                        onConfirm(min(selectedDate, Date()))
                        dismiss()
                    } label: {
                        Label("Conferma dose", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(RoundedRectangle(cornerRadius: 14).fill(green))
                            .foregroundStyle(.white).font(.headline)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal).padding(.bottom, 16)
                }
            }
            .environment(\.locale, kbDeviceLocale())
            .environment(\.calendar, kbDeviceCalendar())
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Conferma dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showDatePickerSheet) {
            NavigationStack {
                ScrollView {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, kbDeviceLocale())
                    .environment(\.calendar, kbDeviceCalendar())
                    .tint(tint)
                    .padding()
                }
                .background(KBTheme.background(colorScheme).ignoresSafeArea())
                .navigationTitle("Scegli data")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { showDatePickerSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") {
                            selectedDate = min(selectedDate, Date())
                            showDatePickerSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTimePickerSheet) {
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, kbDeviceLocale())
                    .environment(\.calendar, kbDeviceCalendar())
                    .tint(tint)
                    Spacer(minLength: 0)
                }
                .padding()
                .background(KBTheme.background(colorScheme).ignoresSafeArea())
                .navigationTitle("Scegli ora")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { showTimePickerSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") {
                            selectedDate = min(selectedDate, Date())
                            showTimePickerSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Visita prescrittrice (dettaglio cura)

private struct TreatmentPrescribingVisitNavRow: View {
    let visitId: String
    let familyId: String
    let childId: String
    let tint: Color
    let colorScheme: ColorScheme
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var visits: [KBMedicalVisit]
    private var visit: KBMedicalVisit? { visits.first }
    
    init(visitId: String, familyId: String, childId: String, tint: Color, colorScheme: ColorScheme) {
        self.visitId = visitId
        self.familyId = familyId
        self.childId = childId
        self.tint = tint
        self.colorScheme = colorScheme
        let vid = visitId
        _visits = Query(filter: #Predicate<KBMedicalVisit> { $0.id == vid })
    }
    
    var body: some View {
        Button {
            coordinator.navigate(to: .pediatricVisitDetail(familyId: familyId, childId: childId, visitId: visitId))
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "stethoscope").foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visita prescrittrice")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(visit.flatMap { $0.reason.isEmpty ? nil : $0.reason } ?? "Visita")
                        .font(.subheadline.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    if let date = visit?.date {
                        Text(
                            date.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .omitted)
                                    .locale(kbDeviceLocale())
                            )
                        )
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private func localizedDayMonthYear(_ date: Date) -> String {
    return date.formatted(
        Date.FormatStyle()
            .day()
            .month(.abbreviated)
            .year()
            .locale(kbDeviceLocale())
    )
}

private func localizedHourMinute(_ date: Date) -> String {
    return date.formatted(
        Date.FormatStyle()
            .hour()
            .minute()
            .locale(kbDeviceLocale())
    )
}

// MARK: - Extend Treatment Sheet

struct ExtendTreatmentSheet: View {
    
    @Bindable var treatment: KBTreatment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var customDays = ""
    @State private var showCustom = false
    
    private let tint    = KBTheme.tint
    private let green   = KBTheme.green
    private let presets = [3, 5, 7, 10]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
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
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(presets, id: \.self) { days in
                        Button { extend(by: days) } label: {
                            VStack(spacing: 2) {
                                Text("\(days)").font(.title2.bold())
                                Text("giorni").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(KBTheme.cardBackground(colorScheme))
                                    .shadow(color: KBTheme.shadow(colorScheme), radius: 4)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showCustom = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "ellipsis").font(.title2.bold())
                            Text("Altro").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(KBTheme.cardBackground(colorScheme))
                                .shadow(color: KBTheme.shadow(colorScheme), radius: 4)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                if showCustom {
                    HStack {
                        TextField("Numero giorni", text: $customDays).keyboardType(.numberPad)
                            .padding(12)
                            .background(KBTheme.inputBackground(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button("Aggiungi") {
                            if let d = Int(customDays), d > 0 { extend(by: d) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(green))
                        .foregroundStyle(.white).buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
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
        treatment.updatedAt = Date(); treatment.updatedBy = uid
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit Schedule Times Sheet

struct EditScheduleTimesSheet: View {
    
    @Bindable var treatment: KBTreatment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var editedTimes: [String] = []
    private let tint = KBTheme.tint
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(tint.opacity(0.1)).frame(width: 52, height: 52)
                        Image(systemName: "clock.badge.checkmark").font(.title2).foregroundStyle(tint)
                    }
                    Text("Personalizza orari").font(.title3.bold())
                    Text(
                        treatment.usesIntervalSchedule
                        ? "Un orario per i giorni di dose (ogni \(treatment.intervalBetweenDosesDays) giorni)."
                        : "Imposta gli orari per \(treatment.dailyFrequency) dos\(treatment.dailyFrequency == 1 ? "e" : "i") giornalier\(treatment.dailyFrequency == 1 ? "a" : "e")"
                    )
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 20).padding(.bottom, 12)
                
                VStack(spacing: 0) {
                    ForEach(editedTimes.indices, id: \.self) { i in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(tint.opacity(0.1)).frame(width: 32, height: 32)
                                Text("\(i+1)").font(.caption.bold()).foregroundStyle(tint)
                            }
                            let t = editedTimes[i]
                            if let p = schedulePeriodForTime(t, slotIndexFallback: i) {
                                TreatmentPeriodBadge(period: p)
                            } else {
                                NeutralPeriodBadge(text: schedulePeriodLabel(t, slotIndexFallback: i))
                            }
                            Spacer()
                            TimePickerField(timeString: $editedTimes[i])
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        if i < editedTimes.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KBTheme.cardBackground(colorScheme))
                        .shadow(color: KBTheme.shadow(colorScheme), radius: 6)
                )
                .padding()
                
                Spacer()
                
                Button { saveTimes() } label: {
                    Text("Salva orari")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                        .foregroundStyle(.white).font(.headline)
                }
                .buttonStyle(.plain)
                .padding(.horizontal).padding(.bottom, 24)
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Orari somministrazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
            .onAppear {
                if treatment.usesIntervalSchedule {
                    let base = treatment.scheduleTimes.isEmpty ? ["08:00"] : treatment.scheduleTimes
                    editedTimes = [base[0]]
                } else {
                    editedTimes = treatment.scheduleTimes.isEmpty
                    ? Array(repeating: "08:00", count: treatment.dailyFrequency)
                    : treatment.scheduleTimes
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func saveTimes() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        treatment.scheduleTimes = treatment.usesIntervalSchedule
            ? Array(editedTimes.prefix(1))
            : editedTimes
        treatment.updatedAt     = Date()
        treatment.updatedBy     = uid
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentUpsert(treatmentId: treatment.id, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if treatment.reminderEnabled {
            TreatmentNotificationManager.cancel(treatmentId: treatment.id)
            TreatmentNotificationManager.schedule(treatment: treatment, childName: "")
        }
        dismiss()
    }
}
