//
//  HomeSummaryGrid.swift
//  KidBox
//
//  Griglia di riepilogo della Home: sei tessere, una per sezione, che dicono
//  cosa c'è dentro senza doverla aprire.
//
//  Perché i dati NON passano dall'AI: il briefing del mattino
//  (`DailyBriefingService`) gira una volta al giorno, resta congelato fino
//  all'indomani, è dietro il piano AI e produce prosa. Le tessere hanno
//  bisogno di conteggi vivi, e quei conteggi li ha già SwiftData — sono gli
//  stessi dati che `buildDailyDataMessage` raccoglie in locale *prima* di
//  spedirli al modello.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth

// MARK: - Preferenza

/// La Dashboard è opt-in: chi non la accende vede la Home di sempre.
/// La chiave sta qui e non nei due `@AppStorage` che la usano, così Home e
/// Impostazioni non possono divergere su una stringa.
enum KBHomeDashboardPreference {
    static let key = "kb_showHomeDashboard"
}

// MARK: - Contenuto di una tessera

/// Cosa mostra una tessera in un dato momento.
private struct SummaryTileContent {
    let id: HomeCardID
    /// Numero o importo. `nil` sulla tessera foto, che al suo posto mostra le miniature.
    let value: String?
    /// Miniature, solo per la tessera foto.
    let thumbnails: [Data]?
    let subtitle: String
    /// Non c'è niente da mostrare: il valore diventa un trattino in secondario.
    /// La tessera resta al suo posto, sparire sposterebbe tutte le altre.
    let isEmpty: Bool
    /// Quanto la sezione merita un posto in Dashboard, dal più urgente al vuoto:
    /// 0 = oggi o in ritardo, 1 = entro sette giorni, 2 = c'è del nuovo non visto,
    /// 3 = ha contenuto ma niente di imminente, 4 = vuota.
    let band: Int

    /// Falso solo per le tessere che raccontano uno stato invece di contare
    /// qualcosa: al posto del numero il sottotitolo prende due righe.
    var showsValueSlot: Bool { thumbnails != nil || value != nil || isEmpty }
}

// MARK: - Tessera

private struct HomeSummaryTile: View {
    let meta: HomeCatMeta
    let content: SummaryTileContent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: meta.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(meta.tint)
                    Text(meta.short)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }

                if let thumbnails = content.thumbnails {
                    thumbnailStrip(thumbnails)
                } else if content.value != nil || content.isEmpty {
                    // Le tessere vuote mostrano il trattino: sparire sposterebbe
                    // tutte le altre.
                    Text(content.value ?? "–")
                        .font(.system(size: 26, weight: .semibold))
                        .kerning(-0.6)
                        .foregroundStyle(content.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                // Chi non ha un numero da mostrare (la posizione) si prende
                // quella riga per il testo.
                Text(content.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(content.showsValueSlot ? 1 : 2)
                    .truncationMode(.tail)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(meta.short))
        .accessibilityValue(Text(content.subtitle))
    }

    /// Quattro caselle sempre: le mancanti restano vuote, così la tessera foto
    /// ha la stessa altezza delle altre anche in un album appena creato.
    private func thumbnailStrip(_ thumbnails: [Data]) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    if index < thumbnails.count, let image = UIImage(data: thumbnails[index]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
}

// MARK: - Griglia

/// Sei tessere in due colonne, sopra le scorciatoie.
///
/// L'ordine non è fisso e non è nemmeno "dal più fresco al più vecchio": la
/// freschezza è la metrica sbagliata, una nota toccata due minuti fa conta meno
/// di una visita fra un'ora. Conta l'imminenza (vedi `band`). Ma solo la PRIMA
/// FILA si riordina: se ballasse tutta la griglia a ogni apertura si perderebbe
/// la memoria delle posizioni.
struct HomeSummaryGrid: View {
    let familyId: String
    let onNavigate: (HomeDestination) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var badge = BadgeManager.shared

    @Query private var events: [KBCalendarEvent]
    @Query private var todos: [KBTodoItem]
    @Query private var groceries: [KBGroceryItem]
    @Query private var notes: [KBNote]
    @Query private var expenses: [KBExpense]
    @Query private var photos: [KBFamilyPhoto]
    @Query private var visits: [KBMedicalVisit]
    @Query private var vaccines: [KBVaccine]
    @Query private var treatments: [KBTreatment]
    @Query private var documents: [KBDocument]
    @Query private var tickets: [KBWalletTicket]
    @Query private var vehicleEvents: [KBVehicleEvent]
    @Query private var homeItems: [KBHomeItem]
    @Query private var petEvents: [KBPetEvent]
    @Query private var trips: [KBTrip]

    @StateObject private var locationObserver = LocationSharingObserver()

    /// Ordine mostrato. Vive in `@State` e non si ricalcola a ogni snapshot:
    /// i numeri sono vivi, le posizioni no.
    @State private var order: [HomeCardID] = HomeSummaryGrid.fallbackOrder

    /// All'`onAppear` le `@Query` possono essere ancora vuote, e un ordine
    /// calcolato sul nulla è l'ordine fisso. Si concede un solo riordino in più,
    /// quando i primi dati arrivano; da lì in poi si muove solo al foreground.
    @State private var didSettle = false

    /// Quante tessere stanno in Dashboard. Tre file da due.
    static let tileCount = 6

    /// Tutte le sezioni che sanno riassumersi, in ordine di preferenza a parità
    /// di urgenza. È anche l'ordine di ripiego quando non c'è ancora niente.
    ///
    /// Fuori di proposito: Chat e Password (contenuto cifrato, una tessera
    /// potrebbe dire solo "quante", e il badge lo dice già), Family (non cambia
    /// mai) e Assistente (è il bottone flottante).
    static let candidates: [HomeCardID] = [
        .calendar, .todo, .care, .shopping, .wallet, .expenses,
        .note, .photos, .location, .documents, .vehicles, .homeItems, .pets, .travel,
    ]

    static let fallbackOrder: [HomeCardID] = Array(candidates.prefix(tileCount))

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(familyId: String, onNavigate: @escaping (HomeDestination) -> Void) {
        self.familyId = familyId
        self.onNavigate = onNavigate

        let fid = familyId
        // Le spese di tutta la vita della famiglia non servono: basta il mese.
        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start
            ?? Date.distantPast

        _events = Query(filter: #Predicate<KBCalendarEvent> {
            $0.familyId == fid && !$0.isDeleted
        }, sort: [SortDescriptor(\KBCalendarEvent.startDate)])

        _todos = Query(filter: #Predicate<KBTodoItem> {
            $0.familyId == fid && !$0.isDeleted && !$0.isDone
        })

        _groceries = Query(filter: #Predicate<KBGroceryItem> {
            $0.familyId == fid && !$0.isDeleted && !$0.isPurchased
        }, sort: [SortDescriptor(\KBGroceryItem.createdAt, order: .reverse)])

        _notes = Query(filter: #Predicate<KBNote> {
            $0.familyId == fid && !$0.isDeleted
        }, sort: [SortDescriptor(\KBNote.updatedAt, order: .reverse)])

        _expenses = Query(filter: #Predicate<KBExpense> {
            $0.familyId == fid && !$0.isDeleted && $0.date >= monthStart
        })

        // Le miniature sono base64 dentro il modello: caricare tutto l'album
        // per mostrarne quattro costerebbe quanto aprire la sezione.
        var photoDescriptor = FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && !$0.isDeleted },
            sortBy: [SortDescriptor(\KBFamilyPhoto.takenAt, order: .reverse)]
        )
        photoDescriptor.fetchLimit = 4
        _photos = Query(photoDescriptor)

        _visits = Query(filter: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && !$0.isDeleted
        }, sort: [SortDescriptor(\KBMedicalVisit.date)])

        _vaccines = Query(filter: #Predicate<KBVaccine> {
            $0.familyId == fid && !$0.isDeleted
        })

        _treatments = Query(filter: #Predicate<KBTreatment> {
            $0.familyId == fid && !$0.isDeleted
        })

        // `extractedText` è una String piena (l'OCR), non external storage:
        // caricare l'archivio intero per contarlo costerebbe più che aprirlo.
        // La Dashboard guarda comunque solo quello che si è mosso di recente.
        let documentsSince = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        _documents = Query(filter: #Predicate<KBDocument> {
            $0.familyId == fid && !$0.isDeleted && $0.updatedAt >= documentsSince
        }, sort: [SortDescriptor(\KBDocument.updatedAt, order: .reverse)])

        _tickets = Query(filter: #Predicate<KBWalletTicket> {
            $0.familyId == fid && !$0.isDeleted
        })

        _vehicleEvents = Query(filter: #Predicate<KBVehicleEvent> {
            $0.familyId == fid && !$0.isDeleted
        }, sort: [SortDescriptor(\KBVehicleEvent.date)])

        _homeItems = Query(filter: #Predicate<KBHomeItem> {
            $0.familyId == fid && !$0.isDeleted
        })

        _petEvents = Query(filter: #Predicate<KBPetEvent> {
            $0.familyId == fid && !$0.isDeleted
        })

        _trips = Query(filter: #Predicate<KBTrip> {
            $0.familyId == fid
        }, sort: [SortDescriptor(\KBTrip.startDate)])
    }

    var body: some View {
        // Stesso occhiello dei gruppi di `HomeCategoryList`, così la Dashboard
        // si legge come una sezione fra le altre e non come un corpo estraneo.
        VStack(alignment: .leading, spacing: 6) {
            HomeEyebrow("Dashboard")

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(order, id: \.self) { id in
                    let meta = HomeCatalog.meta(id)
                    HomeSummaryTile(meta: meta, content: content(for: id)) {
                        handleTap(id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { recomputeOrder() }
        .onChange(of: loadedCount) { _, count in
            guard !didSettle, count > 0 else { return }
            didSettle = true
            recomputeOrder()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { recomputeOrder() }
        }
        .onChange(of: familyId) { _, _ in
            didSettle = false
            recomputeOrder()
        }
    }

    /// Quanti record hanno in mano le query: serve solo a capire quando i dati
    /// sono arrivati, non a decidere l'ordine.
    private var loadedCount: Int {
        events.count + todos.count + groceries.count
            + notes.count + expenses.count + photos.count
            + visits.count + vaccines.count + treatments.count
            + documents.count + tickets.count + vehicleEvents.count
            + homeItems.count + petEvents.count + trips.count
    }

    // MARK: - Ordine

    /// Sceglie le sei tessere fra tutte le sezioni candidate: prima l'urgenza
    /// (la banda), poi l'ordine di preferenza. Le sezioni vuote finiscono in
    /// fondo e restano fuori finché ce n'è una che ha qualcosa da dire.
    ///
    /// Si ricalcola solo all'ingresso, quando arrivano i primi dati e al ritorno
    /// in foreground: se l'insieme cambiasse mentre lo stai guardando sarebbe
    /// peggio che non cambiare mai.
    private func recomputeOrder() {
        let next = Self.candidates
            .filter { isCandidateAvailable($0) }
            .enumerated()
            .sorted { lhs, rhs in
                let bl = content(for: lhs.element).band
                let br = content(for: rhs.element).band
                if bl != br { return bl < br }
                return lhs.offset < rhs.offset
            }
            .prefix(Self.tileCount)
            .map { $0.element }

        if Array(next) != order { order = Array(next) }
    }

    /// Viaggi vive dietro il piano AI: senza, la tessera porterebbe a un muro.
    private func isCandidateAvailable(_ id: HomeCardID) -> Bool {
        id != .travel || KBSubscriptionManager.shared.isAIAccessible
    }

    // MARK: - Contenuto per sezione

    private func content(for id: HomeCardID) -> SummaryTileContent {
        switch id {
        case .calendar:  return calendarContent()
        case .todo:      return todoContent()
        case .care:      return healthContent()
        case .shopping:  return shoppingContent()
        case .wallet:    return walletContent()
        case .expenses:  return expensesContent()
        case .note:      return noteContent()
        case .photos:    return photosContent()
        case .location:  return locationContent()
        case .documents: return documentsContent()
        case .vehicles:  return vehiclesContent()
        case .homeItems: return homeItemsContent()
        case .pets:      return petsContent()
        case .travel:    return travelContent()
        default:
            return empty(id, "")
        }
    }

    /// Tessera senza niente da dire: resta al suo posto con un trattino, e in
    /// banda 4 finisce dietro a tutte quelle che qualcosa ce l'hanno.
    private func empty(_ id: HomeCardID, _ subtitle: String) -> SummaryTileContent {
        SummaryTileContent(id: id, value: nil, thumbnails: nil,
                           subtitle: subtitle, isEmpty: true, band: 4)
    }

    /// Banda di una scadenza: oggi o in ritardo, entro una settimana, o più in là.
    private func band(for date: Date, badge: Int = 0) -> Int {
        if date <= Self.endOfToday { return 0 }
        if date <= Self.inSevenDays { return 1 }
        if badge > 0 { return 2 }
        return 3
    }

    private static var endOfToday: Date {
        Calendar.current.dateInterval(of: .day, for: Date())?.end ?? Date()
    }

    private static var inSevenDays: Date {
        Date().addingTimeInterval(7 * 24 * 60 * 60)
    }

    // MARK: Organizzazione

    private func calendarContent() -> SummaryTileContent {
        let now = Date()
        let uid = currentUid
        let upcoming = events.filter {
            $0.endDate >= now && $0.startDate <= Self.inSevenDays && $0.isVisible(to: uid)
        }
        guard let next = upcoming.first else {
            return empty(.calendar, String(localized: "Niente in agenda"))
        }
        return SummaryTileContent(
            id: .calendar,
            value: "\(upcoming.count)",
            thumbnails: nil,
            subtitle: "\(next.title), \(Self.dayLabel(next.startDate, allDay: next.isAllDay))",
            isEmpty: false,
            band: band(for: next.startDate, badge: badge.calendar)
        )
    }

    private func todoContent() -> SummaryTileContent {
        let uid = currentUid
        let open = todos.filter { $0.isVisible(to: uid) }
        guard !open.isEmpty else {
            return empty(.todo, String(localized: "Niente da fare"))
        }
        // Prima chi ha una scadenza, poi per data: in Home conta cosa scade prima.
        let sorted = open.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let due = sorted[0].dueAt
        return SummaryTileContent(
            id: .todo,
            value: "\(open.count)",
            thumbnails: nil,
            subtitle: sorted[0].title,
            isEmpty: false,
            band: due.map { band(for: $0, badge: badge.todos) } ?? (badge.todos > 0 ? 2 : 3)
        )
    }

    private func shoppingContent() -> SummaryTileContent {
        guard !groceries.isEmpty else {
            return empty(.shopping, String(localized: "Lista vuota"))
        }
        return SummaryTileContent(
            id: .shopping,
            value: "\(groceries.count)",
            thumbnails: nil,
            subtitle: groceries.prefix(3).map(\.name).joined(separator: ", "),
            isEmpty: false,
            band: badge.shopping > 0 ? 2 : 3
        )
    }

    private func noteContent() -> SummaryTileContent {
        let uid = currentUid
        let visible = notes.filter { $0.isVisible(to: uid) }
        guard let latest = visible.first else {
            return empty(.note, String(localized: "Nessuna nota"))
        }
        let title = latest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return SummaryTileContent(
            id: .note,
            value: "\(visible.count)",
            thumbnails: nil,
            subtitle: title.isEmpty ? String(localized: "Senza titolo") : title,
            isEmpty: false,
            band: badge.notes > 0 ? 2 : 3
        )
    }

    // MARK: Famiglia e salute

    /// Visite e vaccini in arrivo; se non ce ne sono, le terapie in corso.
    private func healthContent() -> SummaryTileContent {
        let now = Date()
        let horizon = now.addingTimeInterval(30 * 24 * 60 * 60)

        var upcoming: [(date: Date, title: String)] = visits
            .filter { $0.date >= now && $0.date <= horizon }
            .map { ($0.date, $0.reason) }

        upcoming += vaccines.compactMap { vaccine in
            guard vaccine.status != .administered,
                  let date = vaccine.scheduledDate,
                  date >= now, date <= horizon else { return nil }
            let commercial = vaccine.commercialName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (commercial?.isEmpty == false ? commercial : nil)
                ?? VaccineType(rawValue: vaccine.vaccineTypeRaw)?.displayName
                ?? String(localized: "Vaccino")
            return (date, name)
        }

        if let next = upcoming.min(by: { $0.date < $1.date }) {
            return SummaryTileContent(
                id: .care,
                value: "\(upcoming.count)",
                thumbnails: nil,
                subtitle: "\(next.title), \(Self.dayLabel(next.date, allDay: true))",
                isEmpty: false,
                band: band(for: next.date)
            )
        }

        let ongoing = treatments.filter { $0.isLongTerm || ($0.endDate ?? .distantFuture) >= now }
        guard let treatment = ongoing.first else {
            return empty(.care, String(localized: "Niente in arrivo"))
        }
        return SummaryTileContent(
            id: .care,
            value: "\(ongoing.count)",
            thumbnails: nil,
            subtitle: treatment.drugName,
            isEmpty: false,
            band: 3
        )
    }

    // MARK: Documenti e denaro

    private func documentsContent() -> SummaryTileContent {
        let uid = currentUid
        let recent = documents.filter { $0.isVisibleToCurrentUser(currentUid: uid) }
        guard let latest = recent.first else {
            return empty(.documents, String(localized: "Niente di recente"))
        }
        return SummaryTileContent(
            id: .documents,
            value: "\(recent.count)",
            thumbnails: nil,
            subtitle: latest.title,
            isEmpty: false,
            band: badge.documents > 0 ? 2 : 3
        )
    }

    private func expensesContent() -> SummaryTileContent {
        let total = expenses.reduce(0) { $0 + $1.amount }
        let month = Date().formatted(.dateTime.month(.wide).locale(kbDeviceLocale()))
        guard total > 0 else {
            return empty(.expenses, String(localized: "Nessuna spesa a \(month)"))
        }
        return SummaryTileContent(
            id: .expenses,
            value: total.formatted(.currency(code: "EUR").precision(.fractionLength(0))),
            thumbnails: nil,
            subtitle: month,
            isEmpty: false,
            band: badge.expenses > 0 ? 2 : 3
        )
    }

    /// Biglietti e prenotazioni con una data futura: quelli senza data non
    /// scadono, quindi non hanno niente da anticipare in Home.
    private func walletContent() -> SummaryTileContent {
        let now = Date()
        let uid = currentUid
        let upcoming = tickets
            .filter { $0.isVisible(to: uid) }
            .compactMap { ticket -> (date: Date, title: String)? in
                guard let date = ticket.eventDate, (ticket.eventEndDate ?? date) >= now else { return nil }
                return (date, ticket.title)
            }
            .sorted { $0.date < $1.date }

        guard let next = upcoming.first else {
            return empty(.wallet, String(localized: "Niente in arrivo"))
        }
        return SummaryTileContent(
            id: .wallet,
            value: "\(upcoming.count)",
            thumbnails: nil,
            subtitle: "\(next.title), \(Self.dayLabel(next.date, allDay: true))",
            isEmpty: false,
            band: band(for: next.date, badge: badge.wallet)
        )
    }

    // MARK: Vita quotidiana

    private func locationContent() -> SummaryTileContent {
        guard locationObserver.isSharing else {
            return empty(.location, String(localized: "Non stai condividendo"))
        }
        return SummaryTileContent(
            id: .location,
            value: nil,
            thumbnails: nil,
            subtitle: String(localized: "Stai condividendo la posizione"),
            isEmpty: false,
            band: 3
        )
    }

    private func photosContent() -> SummaryTileContent {
        guard let latest = photos.first else {
            return empty(.photos, String(localized: "Nessuna foto"))
        }
        return SummaryTileContent(
            id: .photos,
            value: nil,
            thumbnails: photos.compactMap(\.thumbnailData),
            subtitle: Self.addedLabel(latest.takenAt),
            isEmpty: false,
            band: 3
        )
    }

    private func vehiclesContent() -> SummaryTileContent {
        let now = Date()
        let upcoming = vehicleEvents.filter { $0.date >= now }
        guard let next = upcoming.first else {
            return empty(.vehicles, String(localized: "Nessuna scadenza"))
        }
        return SummaryTileContent(
            id: .vehicles,
            value: "\(upcoming.count)",
            thumbnails: nil,
            subtitle: "\(next.title), \(Self.dayLabel(next.date, allDay: true))",
            isEmpty: false,
            band: band(for: next.date)
        )
    }

    /// Garanzie che stanno per scadere e manutenzioni in arrivo, insieme:
    /// per chi guarda sono la stessa cosa, una data che si avvicina.
    private func homeItemsContent() -> SummaryTileContent {
        let now = Date()
        let deadlines: [(date: Date, title: String)] = homeItems.flatMap { item -> [(date: Date, title: String)] in
            var found: [(date: Date, title: String)] = []
            if let warranty = item.warrantyExpiryDate, warranty >= now { found.append((warranty, item.name)) }
            if let service = item.nextServiceDate, service >= now { found.append((service, item.name)) }
            return found
        }.sorted { $0.date < $1.date }

        guard let next = deadlines.first else {
            return empty(.homeItems, String(localized: "Nessuna scadenza"))
        }
        return SummaryTileContent(
            id: .homeItems,
            value: "\(deadlines.count)",
            thumbnails: nil,
            subtitle: "\(next.title), \(Self.dayLabel(next.date, allDay: true))",
            isEmpty: false,
            band: band(for: next.date)
        )
    }

    private func petsContent() -> SummaryTileContent {
        let now = Date()
        let due = petEvents
            .compactMap { event -> (date: Date, title: String)? in
                guard let next = event.nextDueDate, next >= now else { return nil }
                return (next, event.title)
            }
            .sorted { $0.date < $1.date }

        guard let next = due.first else {
            return empty(.pets, String(localized: "Nessuna scadenza"))
        }
        return SummaryTileContent(
            id: .pets,
            value: "\(due.count)",
            thumbnails: nil,
            subtitle: "\(next.title), \(Self.dayLabel(next.date, allDay: true))",
            isEmpty: false,
            band: band(for: next.date)
        )
    }

    private func travelContent() -> SummaryTileContent {
        let now = Date()
        let upcoming = trips.filter { $0.endDate >= now }
        guard let next = upcoming.first else {
            return empty(.travel, String(localized: "Nessun viaggio"))
        }
        return SummaryTileContent(
            id: .travel,
            value: "\(upcoming.count)",
            thumbnails: nil,
            subtitle: "\(next.name), \(Self.dayLabel(next.startDate, allDay: true))",
            isEmpty: false,
            band: band(for: next.startDate)
        )
    }

    // MARK: - Etichette

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    /// "oggi 08:00", "domani 16:00", "ven 05/09".
    private static func dayLabel(_ date: Date, allDay: Bool) -> String {
        let calendar = Calendar.current
        if allDay {
            if calendar.isDateInToday(date) { return String(localized: "oggi") }
            if calendar.isDateInTomorrow(date) { return String(localized: "domani") }
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits)
                .locale(kbDeviceLocale()))
        }
        let time = date.formatted(.dateTime.hour().minute().locale(kbDeviceLocale()))
        if calendar.isDateInToday(date) { return String(localized: "oggi \(time)") }
        if calendar.isDateInTomorrow(date) { return String(localized: "domani \(time)") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits)
            .locale(kbDeviceLocale()))
    }

    private static func addedLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "aggiunte oggi") }
        if calendar.isDateInYesterday(date) { return String(localized: "aggiunte ieri") }
        let day = date.formatted(.dateTime.day().month(.wide).locale(kbDeviceLocale()))
        return String(localized: "ultima il \(day)")
    }

    // MARK: - Tap

    /// Stessi effetti collaterali della riga corrispondente in `HomeCategoryList`:
    /// una tessera e la sua riga devono comportarsi allo stesso modo.
    private func handleTap(_ id: HomeCardID) {
        HomeShortcutUsage.shared.record(id.rawValue)
        if let key = HomeCatalog.meta(id).usageKey {
            FABUsageTracker.shared.record(key)
        }
        KBLog.navigation.kbDebug("Home: tap summary \(id.rawValue)")

        // Le sezioni che azzerano un contatore quando le apri lo azzerano anche
        // da qui: una tessera e la sua riga non devono comportarsi diversamente.
        switch id {
        case .shopping:
            clearBadge { BadgeManager.shared.clearShopping() } field: { .shopping }
        case .expenses:
            clearBadge { BadgeManager.shared.clearExpenses() } field: { .expenses }
        case .note:
            clearBadge { BadgeManager.shared.clearNotes() } field: { .notes }
        case .wallet:
            clearBadge { BadgeManager.shared.clearWallet() } field: { .wallet }
        default:
            break
        }

        switch id {
        case .calendar:  onNavigate(.calendar(familyId: familyId))
        case .todo:      onNavigate(.todo)
        case .care:      onNavigate(.pediatric(familyId: familyId, childId: ""))
        case .shopping:  onNavigate(.shopping(familyId: familyId))
        case .wallet:    onNavigate(.wallet(familyId: familyId))
        case .expenses:  onNavigate(.expenses(familyId: familyId))
        case .note:      onNavigate(.notes(familyId: familyId))
        case .photos:    onNavigate(.familyPhotos(familyId: familyId))
        case .location:  onNavigate(.familyLocation(familyId: familyId))
        case .documents: onNavigate(.document)
        case .vehicles:  onNavigate(.vehicles(familyId: familyId))
        case .homeItems: onNavigate(.homeItems(familyId: familyId))
        case .pets:      onNavigate(.pets(familyId: familyId))
        case .travel:    onNavigate(.travel(familyId: familyId))
        default:         break
        }
    }

    private func clearBadge(
        _ clear: @escaping () -> Void,
        field: @escaping () -> CountersField
    ) {
        let fid = familyId
        Task { @MainActor in
            clear()
            await CountersService.shared.reset(familyId: fid, field: field())
        }
    }
}
