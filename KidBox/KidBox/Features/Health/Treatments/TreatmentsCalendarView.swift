//
//  TreatmentsCalendarView.swift
//  KidBox
//
//  Vista per giorno di tutte le cure di un figlio: in alto il giorno, sotto le
//  dosi di tutte le cure in ordine di orario, con gli stessi pulsanti della
//  scheda cura (preso con orario, saltato, annulla). Si passa da un giorno
//  all'altro scorrendo in orizzontale (o con le frecce).
//
//  Le dosi si calcolano dalla cura (data di inizio, durata, orari, intervallo)
//  e dai `KBDoseLog`; la scrittura passa da `TreatmentDoseActions`.
//

import SwiftUI
import SwiftData

// MARK: - Modello di una dose del calendario

private enum CalendarDoseState: Equatable {
    case taken(Date?)
    case skipped
    case pending
}

private struct CalendarDose: Identifiable {
    let treatment: KBTreatment
    let dayNumber: Int
    let slotIndex: Int
    let scheduledTime: String
    /// Minuti dalla mezzanotte, per ordinare le dosi del giorno.
    let sortMinutes: Int
    let state: CalendarDoseState
    let isFutureDay: Bool
    let isPastDay: Bool

    var id: String { "\(treatment.id)|\(dayNumber)|\(slotIndex)" }
}

private struct CalendarConfirmItem: Identifiable {
    let id = UUID()
    let treatment: KBTreatment
    let context: ConfirmDoseContext
}

// MARK: - View

struct TreatmentsCalendarView: View {

    let familyId: String
    let childId: String
    let childName: String
    let treatments: [KBTreatment]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var logs: [KBDoseLog]

    /// Giorno mostrato, come numero di giorni dal riferimento (indipendente dall'intervallo di pagine).
    @State private var position: Int?
    @State private var confirmItem: CalendarConfirmItem? = nil

    private let tint = KBTheme.tint
    private let cal = Calendar.current
    private static let referenceDay = Date(timeIntervalSinceReferenceDate: 0)

    init(familyId: String, childId: String, childName: String, treatments: [KBTreatment]) {
        self.familyId = familyId
        self.childId = childId
        self.childName = childName
        self.treatments = treatments
        let fid = familyId, cid = childId
        _logs = Query(filter: #Predicate<KBDoseLog> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        let c = Calendar.current
        let ref = c.startOfDay(for: Self.referenceDay)
        let today = c.dateComponents([.day], from: ref, to: c.startOfDay(for: Date())).day ?? 0
        _position = State(initialValue: today)
    }

    // MARK: - Giorni

    private func dayId(_ date: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: Self.referenceDay), to: cal.startOfDay(for: date)).day ?? 0
    }

    private func date(forId id: Int) -> Date {
        cal.date(byAdding: .day, value: id, to: cal.startOfDay(for: Self.referenceDay)) ?? Date()
    }

    private var todayId: Int { dayId(Date()) }
    private var selectedId: Int { position ?? todayId }

    /// Dal primo giorno utile (inizio della cura più vecchia, almeno una settimana fa)
    /// all'ultimo (fine della cura più lunga, almeno due settimane avanti).
    private var dayRange: ClosedRange<Int> {
        let today = todayId
        var lo = today - 7
        var hi = today + 14
        for t in treatments where !t.isDeleted {
            let s = dayId(t.startDate)
            lo = min(lo, s)
            hi = max(hi, t.isLongTerm ? today + 30 : s + t.durationDays - 1)
        }
        return max(lo, today - 400) ... min(hi, today + 400)
    }

    private func step(_ delta: Int) {
        let target = min(max(selectedId + delta, dayRange.lowerBound), dayRange.upperBound)
        withAnimation(.easeInOut(duration: 0.25)) { position = target }
    }

    private func goToToday() {
        withAnimation(.easeInOut(duration: 0.25)) { position = todayId }
    }

    // MARK: - Calcolo delle dosi

    private var logIndex: [String: KBDoseLog] {
        var dict: [String: KBDoseLog] = [:]
        for l in logs { dict["\(l.treatmentId)|\(l.dayNumber)|\(l.slotIndex)"] = l }
        return dict
    }

    private func doses(on day: Date, index: [String: KBDoseLog]) -> [CalendarDose] {
        let dayStart = cal.startOfDay(for: day)
        let todayStart = cal.startOfDay(for: Date())
        var result: [CalendarDose] = []

        for t in treatments where !t.isDeleted {
            let offset = cal.dateComponents([.day], from: cal.startOfDay(for: t.startDate), to: dayStart).day ?? -1
            guard offset >= 0 else { continue }
            if !t.isLongTerm && offset >= t.durationDays { continue }

            let times = t.scheduleTimes
            let slots: [Int]
            if t.usesIntervalSchedule {
                slots = t.isScheduledDoseDay(calendarDayOffsetFromStart: offset) ? [0] : []
            } else {
                slots = Array(times.indices)
            }

            for slot in slots {
                let time = times.indices.contains(slot) ? times[slot] : (times.first ?? "08:00")
                let log = index["\(t.id)|\(offset + 1)|\(slot)"]
                // Cura interrotta: restano solo le dosi già registrate.
                if !t.isActive && log == nil { continue }
                let state: CalendarDoseState
                if let log {
                    state = log.taken ? .taken(log.takenAt) : .skipped
                } else {
                    state = .pending
                }
                result.append(CalendarDose(
                    treatment: t,
                    dayNumber: offset + 1,
                    slotIndex: slot,
                    scheduledTime: time,
                    sortMinutes: TreatmentSchedulePeriod.parseScheduleTimeToMinutesOfDay(time) ?? Int.max,
                    state: state,
                    isFutureDay: dayStart > todayStart,
                    isPastDay: dayStart < todayStart
                ))
            }
        }
        return result.sorted {
            if $0.sortMinutes != $1.sortMinutes { return $0.sortMinutes < $1.sortMinutes }
            return $0.treatment.drugName.localizedCaseInsensitiveCompare($1.treatment.drugName) == .orderedAscending
        }
    }

    // MARK: - Formati

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    private static let dayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return f
    }()

    /// «Ieri» / «Oggi» / «Domani» nella lingua dell'app (vuoto per gli altri giorni).
    private static let relativeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    private static let hourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f
    }()

    private static func hourMinute(_ date: Date) -> String { hourMinuteFormatter.string(from: date) }

    private func dayTitle(_ day: Date) -> String {
        let sameYear = cal.isDate(day, equalTo: Date(), toGranularity: .year)
        return Self.upperFirst((sameYear ? Self.dayFormatter : Self.dayYearFormatter).string(from: day))
    }

    /// Solo la prima lettera maiuscola («Martedì 10 novembre»): `capitalized` maiuscolizzava anche il mese.
    private static func upperFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private func relativeLabel(forId id: Int) -> String? {
        guard abs(id - todayId) <= 1 else { return nil }
        return Self.upperFirst(Self.relativeFormatter.string(from: date(forId: id)))
    }

    // MARK: - Body

    var body: some View {
        let index = logIndex
        VStack(spacing: 0) {
            header(index: index)
            pager(index: index)
        }
        .background(KBTheme.background(colorScheme))
        .sheet(item: $confirmItem) { item in
            ConfirmDoseSheet(treatment: item.treatment, childName: childName, context: item.context) { takenAt in
                TreatmentDoseActions.markTaken(
                    treatment: item.treatment,
                    dayNumber: item.context.dayNumber,
                    slotIndex: item.context.slotIndex,
                    scheduledTime: item.context.scheduledTime,
                    takenAt: takenAt,
                    modelContext: modelContext
                )
            }
        }
    }

    // MARK: - Intestazione: il giorno

    private func header(index: [String: KBDoseLog]) -> some View {
        let id = selectedId
        let day = date(forId: id)
        let list = doses(on: day, index: index)
        let done = list.filter { if case .pending = $0.state { return false } else { return true } }.count
        return HStack(spacing: 4) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 40, height: 44)
            }
            .disabled(id <= dayRange.lowerBound)
            .accessibilityLabel(Text("Giorno precedente"))

            VStack(spacing: 2) {
                if let rel = relativeLabel(forId: id) {
                    Text(verbatim: rel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(verbatim: dayTitle(day))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if list.isEmpty {
                    Text(verbatim: " ").font(.caption)
                } else {
                    Text("\(done) di \(list.count) dosi")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(done == list.count ? Color.green : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if id != todayId { goToToday() } }

            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 40, height: 44)
            }
            .disabled(id >= dayRange.upperBound)
            .accessibilityLabel(Text("Giorno successivo"))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(KBTheme.cardBackground(colorScheme))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Pagine

    private func pager(index: [String: KBDoseLog]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(dayRange), id: \.self) { id in
                    dayPage(id, index: index)
                        .containerRelativeFrame(.horizontal)
                        .id(id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
    }

    private func dayPage(_ id: Int, index: [String: KBDoseLog]) -> some View {
        let day = date(forId: id)
        let list = doses(on: day, index: index)
        return ScrollView {
            VStack(spacing: 10) {
                if list.isEmpty {
                    Text("Nessuna dose programmata per questo giorno.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.cardBackground(colorScheme)))
                } else {
                    ForEach(list) { dose in doseRow(dose) }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Riga di una dose

    private func doseAmount(_ t: KBTreatment) -> String {
        let v = t.dosageValue
        let number = v == v.rounded()
            ? String(format: "%.0f", v)
            : v.formatted(.number.precision(.fractionLength(0...2)).locale(kbDeviceLocale()))
        return "\(number) \(t.dosageUnit)"
    }

    /// Da prendere e l'orario è già passato (o il giorno è passato).
    private func isOverdue(_ dose: CalendarDose) -> Bool {
        guard case .pending = dose.state else { return false }
        if dose.isFutureDay { return false }
        if dose.isPastDay { return true }
        guard dose.sortMinutes != Int.max else { return false }
        let now = Date()
        let minutesNow = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return dose.sortMinutes < minutesNow
    }

    private func doseRow(_ dose: CalendarDose) -> some View {
        let t = dose.treatment
        let taken: Bool = { if case .taken = dose.state { return true } else { return false } }()
        let skipped = dose.state == .skipped
        let period = TreatmentSchedulePeriod.from(scheduleTime: dose.scheduledTime)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(taken ? tint.opacity(0.1) : skipped ? Color.orange.opacity(0.1) : KBTheme.inputBackground(colorScheme))
                    .frame(width: 40, height: 40)
                Image(systemName: skipped ? "xmark" : (taken ? "checkmark" : "clock.fill"))
                    .foregroundStyle(taken ? tint : skipped ? .orange : .secondary)
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: dose.scheduledTime).font(.subheadline.bold())
                    if let period { TreatmentPeriodBadge(period: period) }
                }
                Text(verbatim: t.drugName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(verbatim: doseAmount(t)).font(.caption).foregroundStyle(tint)
                if case .taken(let at) = dose.state, let at {
                    Text("Presa: \(Self.hourMinute(at))").font(.caption).foregroundStyle(.green)
                } else if skipped {
                    Label("Saltata", systemImage: "xmark.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if isOverdue(dose) {
                    Text("Non registrata").font(.caption).foregroundStyle(.red)
                } else {
                    Text("Da assumere").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)
            doseButtons(dose, taken: taken, skipped: skipped)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 4, x: 0, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            coordinator.navigate(to: .pediatricTreatmentDetail(
                familyId: familyId, childId: childId, treatmentId: t.id
            ))
        }
    }

    @ViewBuilder
    private func doseButtons(_ dose: CalendarDose, taken: Bool, skipped: Bool) -> some View {
        let t = dose.treatment
        if taken {
            Button {
                TreatmentDoseActions.undo(treatment: t, dayNumber: dose.dayNumber, slotIndex: dose.slotIndex, modelContext: modelContext)
            } label: {
                Text("Annulla").font(.caption).foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().stroke(tint.opacity(0.4)))
            }
            .buttonStyle(.plain)
        } else if skipped {
            Button {
                TreatmentDoseActions.undo(treatment: t, dayNumber: dose.dayNumber, slotIndex: dose.slotIndex, modelContext: modelContext)
            } label: {
                Text("Riprendi").font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().stroke(Color.orange.opacity(0.4)))
            }
            .buttonStyle(.plain)
        } else if dose.isFutureDay || !t.isActive {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                Button {
                    TreatmentDoseActions.markSkipped(
                        treatment: t, dayNumber: dose.dayNumber, slotIndex: dose.slotIndex,
                        scheduledTime: dose.scheduledTime, modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(KBTheme.inputBackground(colorScheme)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Salta dose"))

                Button {
                    confirmItem = CalendarConfirmItem(
                        treatment: t,
                        context: ConfirmDoseContext(
                            dayNumber: dose.dayNumber,
                            slotIndex: dose.slotIndex,
                            scheduledTime: dose.scheduledTime,
                            drugName: t.drugName,
                            dosageValue: t.dosageValue,
                            dosageUnit: t.dosageUnit
                        )
                    )
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.green))
                        .foregroundStyle(.white)
                        .font(.subheadline.bold())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Segna come presa"))
            }
        }
    }
}
