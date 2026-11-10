//
//  TreatmentsCalendarView.swift
//  KidBox
//
//  Vista per giorno di tutte le cure di un figlio: in alto il giorno, sotto una
//  linea del tempo con le ore (come il Calendario) e le dosi di tutte le cure
//  come card piccole sull'ora giusta, con gli stessi pulsanti della scheda cura
//  (preso con orario, saltato, annulla). Si passa da un giorno all'altro
//  scorrendo in orizzontale (o con le frecce).
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

    // Misure della linea del tempo
    private static let cardHeight: CGFloat = 50
    private static let cardGap: CGFloat = 4
    private static let minHourHeight: CGFloat = 44
    private static let gutterWidth: CGFloat = 46

    /// Ora (0-23) a cui sta una dose nella griglia.
    private func hour(of dose: CalendarDose) -> Int {
        guard dose.sortMinutes != Int.max else { return 8 }
        return min(max(dose.sortMinutes / 60, 0), 23)
    }

    /// Una pagina = un giorno: le ore a sinistra, le dosi come card piccole sull'ora giusta.
    /// Se in un'ora ci sono più dosi le card si impilano e la riga dell'ora si allunga
    /// (affiancate sarebbero troppo strette per i pulsanti).
    private func dayPage(_ id: Int, index: [String: KBDoseLog]) -> some View {
        let day = date(forId: id)
        let list = doses(on: day, index: index)
        let byHour = Dictionary(grouping: list, by: { hour(of: $0) })
        let heights: [CGFloat] = (0..<24).map { h in
            let n = byHour[h]?.count ?? 0
            return max(Self.minHourHeight, CGFloat(n) * (Self.cardHeight + Self.cardGap) + Self.cardGap)
        }
        var tops: [CGFloat] = []
        var run: CGFloat = 0
        for h in heights { tops.append(run); run += h }
        let isToday = id == todayId
        // Dove far partire la scroll: un'ora prima dell'ora attuale (oggi) o della prima dose.
        let startHour: Int = {
            if isToday { return max(0, cal.component(.hour, from: Date()) - 1) }
            if let first = list.map({ hour(of: $0) }).min() { return max(0, first - 1) }
            return 7
        }()
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if list.isEmpty {
                        Text("Nessuna dose programmata per questo giorno.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { h in
                                hourRow(h, doses: byHour[h] ?? [], height: heights[h])
                                    .id(h)
                            }
                        }
                        if isToday {
                            TimelineView(.everyMinute) { ctx in
                                nowLine(at: ctx.date, tops: tops, heights: heights)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(startHour, anchor: .top) }
            }
        }
    }

    private func hourRow(_ h: Int, doses: [CalendarDose], height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(verbatim: String(format: "%02d:00", h))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Self.gutterWidth, alignment: .trailing)
                .padding(.trailing, 6)
                .offset(y: -6)
            VStack(spacing: Self.cardGap) {
                ForEach(doses) { dose in doseCard(dose) }
            }
            .padding(.top, Self.cardGap)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .top)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
            }
        }
        .frame(height: height, alignment: .top)
    }

    /// La linea rossa dell'ora attuale, come nel calendario.
    private func nowLine(at date: Date, tops: [CGFloat], heights: [CGFloat]) -> some View {
        let h = min(max(cal.component(.hour, from: date), 0), 23)
        let m = cal.component(.minute, from: date)
        let y = tops[h] + heights[h] * CGFloat(m) / 60
        return HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
                .padding(.leading, Self.gutterWidth + 6 - 3.5)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
        .offset(y: y - 3.5)
        .allowsHitTesting(false)
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

    /// Un colore stabile per cura, per riconoscerla a colpo d'occhio come i calendari del Calendario.
    private func color(for t: KBTreatment) -> Color {
        let palette: [Color] = [
            tint, Color(red: 0.20, green: 0.52, blue: 0.95), Color(red: 0.10, green: 0.68, blue: 0.62),
            Color(red: 0.92, green: 0.34, blue: 0.55), Color(red: 0.95, green: 0.55, blue: 0.15),
            Color(red: 0.38, green: 0.36, blue: 0.85)
        ]
        // Per posizione fra le cure (ordinate per id, quindi stabile): cure diverse, colori diversi.
        let index = treatments.map(\.id).sorted().firstIndex(of: t.id) ?? 0
        return palette[index % palette.count]
    }

    private func doseCard(_ dose: CalendarDose) -> some View {
        let t = dose.treatment
        let taken: Bool = { if case .taken = dose.state { return true } else { return false } }()
        let skipped = dose.state == .skipped
        let accent = color(for: t)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if taken {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    } else if skipped {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Text(verbatim: dose.scheduledTime)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: t.drugName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(verbatim: doseAmount(t)).font(.caption).foregroundStyle(accent)
                    if case .taken(let at) = dose.state, let at {
                        Text("Presa: \(Self.hourMinute(at))").font(.caption).foregroundStyle(.green)
                    } else if skipped {
                        Text("Saltata").font(.caption).foregroundStyle(.orange)
                    } else if isOverdue(dose) {
                        Text("Non registrata").font(.caption).foregroundStyle(.red)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            doseButtons(dose, taken: taken, skipped: skipped)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: Self.cardHeight)
        .background(accent.opacity(taken ? 0.10 : 0.18))
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3.5) }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(taken || skipped ? 0.8 : 1)
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
                Text("Annulla").font(.caption2).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().stroke(tint.opacity(0.4)))
            }
            .buttonStyle(.plain)
        } else if skipped {
            Button {
                TreatmentDoseActions.undo(treatment: t, dayNumber: dose.dayNumber, slotIndex: dose.slotIndex, modelContext: modelContext)
            } label: {
                Text("Riprendi").font(.caption2).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().stroke(Color.orange.opacity(0.4)))
            }
            .buttonStyle(.plain)
        } else if dose.isFutureDay || !t.isActive {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Button {
                    TreatmentDoseActions.markSkipped(
                        treatment: t, dayNumber: dose.dayNumber, slotIndex: dose.slotIndex,
                        scheduledTime: dose.scheduledTime, modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
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
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.green))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Segna come presa"))
            }
        }
    }
}
