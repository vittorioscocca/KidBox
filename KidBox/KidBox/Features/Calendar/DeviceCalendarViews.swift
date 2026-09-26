//
//  DeviceCalendarViews.swift
//  KidBox
//
//  Le schermate dei calendari del telefono dentro il calendario KidBox:
//  la scelta dei calendari, la scheda di un evento (sola lettura, con
//  «Copia in KidBox»), l'invito a collegarli e la riga dell'elenco.
//  Il motore sta in `DeviceCalendarStore`.
//

import SwiftUI
import UIKit

// MARK: - Prefill per «Copia in KidBox»

/// I campi di un evento del telefono che passano alla scheda «Nuovo evento».
/// Categoria, visibilità e promemoria restano da scegliere: sono cose di
/// KidBox che Google non conosce.
struct CalendarEventPrefill: Identifiable {
    let id = UUID()
    let title:     String
    let notes:     String?
    let location:  String?
    let startDate: Date
    let endDate:   Date
    let isAllDay:  Bool

    init(_ event: DeviceCalendarEvent) {
        title     = event.title
        notes     = event.notes
        location  = event.location
        startDate = event.startDate
        endDate   = event.endDate
        isAllDay  = event.isAllDay
    }
}

// MARK: - Scelta dei calendari

struct DeviceCalendarSettingsView: View {

    let familyId: String

    @ObservedObject private var store = DeviceCalendarStore.shared
    @ObservedObject private var feedStore = CalendarFeedStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false
    @State private var isAddingFeed = false
    @State private var feedToRemove: CalendarFeed?
    @State private var feedErrorMessage: String?
    @State private var connectProvider: ConnectProvider?

    private var calendarsBySource: [(source: String, calendars: [DeviceCalendarInfo])] {
        var order: [String] = []
        var groups: [String: [DeviceCalendarInfo]] = [:]
        for cal in store.calendars {
            if groups[cal.sourceTitle] == nil { order.append(cal.sourceTitle) }
            groups[cal.sourceTitle, default: []].append(cal)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    accessRow
                } header: {
                    Text("Da questo telefono")
                } footer: {
                    Text("KidBox legge i calendari già configurati su questo dispositivo (Google, iCloud, Outlook) e si aggiorna da solo quando cambiano. Gli eventi restano sul telefono: la famiglia non li vede, a meno che tu non ne copi uno in KidBox.")
                }

                if store.isShowing {
                    ForEach(calendarsBySource, id: \.source) { group in
                        Section(group.source.isEmpty ? String(localized: "Altri calendari") : group.source) {
                            ForEach(group.calendars) { cal in
                                Toggle(isOn: Binding(
                                    get: { store.isVisible(calendarId: cal.id) },
                                    set: { store.setVisible($0, calendarId: cal.id) }
                                )) {
                                    HStack(spacing: 10) {
                                        Circle().fill(cal.color).frame(width: 12, height: 12)
                                        Text(cal.title)
                                    }
                                }
                            }
                        }
                    }
                }

                connectSection
                feedsSection
            }
            .navigationTitle("Calendari collegati")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .onAppear {
                store.refreshAuthorization()
                store.reload()
                feedStore.start(familyId: familyId)
            }
            .sheet(isPresented: $isAddingFeed) {
                AddCalendarFeedView(familyId: familyId)
            }
            .alert(
                connectProvider?.title ?? "",
                isPresented: Binding(
                    get: { connectProvider != nil },
                    set: { if !$0 { connectProvider = nil } }
                ),
                presenting: connectProvider
            ) { _ in
                Button("Apri Impostazioni") {
                    connectProvider = nil
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Annulla", role: .cancel) { connectProvider = nil }
            } message: { provider in
                Text(provider.steps)
            }
            .confirmationDialog(
                String(format: String(localized: "Togliere «%@»?"), feedToRemove?.name ?? ""),
                isPresented: Binding(
                    get: { feedToRemove != nil },
                    set: { if !$0 { feedToRemove = nil } }
                ),
                titleVisibility: .visible,
                presenting: feedToRemove
            ) { feed in
                Button("Togli", role: .destructive) {
                    feedToRemove = nil
                    Task {
                        if case .failed(let reason) = await feedStore.delete(familyId: familyId, feedId: feed.id) {
                            feedErrorMessage = CalendarFeedStore.message(for: reason)
                        }
                    }
                }
                Button("Annulla", role: .cancel) { feedToRemove = nil }
            } message: { _ in
                Text("Sparisce dal calendario di tutta la famiglia. Gli eventi già copiati in KidBox restano.")
            }
            .alert(
                "Calendari iscritti",
                isPresented: Binding(
                    get: { feedErrorMessage != nil },
                    set: { if !$0 { feedErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { feedErrorMessage = nil }
            } message: {
                Text(feedErrorMessage ?? "")
            }
        }
    }

    /// Google e Outlook senza OAuth: un account aggiunto all'iPhone porta con
    /// sé i suoi calendari, e KidBox li legge con EventKit come gli altri
    /// (`EKEventStoreChanged` li fa comparire al ritorno). Apple non permette
    /// di aprire direttamente la schermata degli account: si danno i passi.
    private var connectSection: some View {
        Section {
            Button {
                connectProvider = .google
            } label: {
                Label("Collega Google Calendar", systemImage: "person.crop.circle.badge.plus")
            }
            Button {
                connectProvider = .outlook
            } label: {
                Label("Collega Outlook", systemImage: "person.crop.circle.badge.plus")
            }
        } header: {
            Text("Collega un account")
        } footer: {
            Text("Un account aggiunto all'iPhone porta con sé i suoi calendari: dopo l'accesso compaiono qui da soli.")
        }
    }

    /// I calendari iscritti da link: li vede tutta la famiglia.
    private var feedsSection: some View {
        Section {
            ForEach(feedStore.feeds) { feed in
                HStack(spacing: 10) {
                    Circle().fill(feed.color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feed.name)
                        if feed.lastError != nil {
                            Text("Ultimo aggiornamento non riuscito")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(String(format: String(localized: "Eventi: %lld"), feed.eventCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        feedToRemove = feed
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Togli")
                }
            }
            Button {
                isAddingFeed = true
            } label: {
                Label("Aggiungi da link", systemImage: "link.badge.plus")
            }
        } header: {
            Text("Calendari iscritti")
        } footer: {
            Text("Il link di un calendario pubblicato: scuola, squadra, festività, o l'indirizzo iCal di un Google Calendar. Gli eventi li vede tutta la famiglia e si aggiornano da soli ogni qualche ora.")
        }
    }

    @ViewBuilder
    private var accessRow: some View {
        if store.hasAccess {
            Toggle("Mostra i calendari del telefono", isOn: $store.isEnabled)
        } else if store.isDenied {
            VStack(alignment: .leading, spacing: 8) {
                Text("L'accesso ai calendari è negato.")
                    .font(.subheadline.weight(.semibold))
                Text("Per mostrarli qui, consenti l'accesso completo ai calendari nelle Impostazioni.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            .padding(.vertical, 4)
        } else {
            Button {
                isRequesting = true
                Task {
                    await store.requestAccess()
                    isRequesting = false
                }
            } label: {
                HStack {
                    Label("Consenti l'accesso ai calendari", systemImage: "calendar.badge.checkmark")
                    Spacer()
                    if isRequesting { ProgressView() }
                }
            }
            .disabled(isRequesting)
        }
    }
}

// MARK: - Invito a collegarli

/// Compare nel calendario finché l'utente non ha mai risposto alla domanda
/// di sistema: è la risposta a «il mio calendario è già su Google».
struct DeviceCalendarPromptCard: View {

    let onConnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Usi già Google Calendar o iCloud?")
                    .font(.subheadline.weight(.semibold))
                Text("Vedi qui i loro eventi accanto a quelli della famiglia. Restano sul telefono e li vedi solo tu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Mostra i miei calendari", action: onConnect)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Riga dell'elenco del giorno

struct DeviceCalendarEventRow: View {
    let event: DeviceCalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(event.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body)

                HStack(spacing: 6) {
                    if event.isAllDay {
                        Text("Tutto il giorno")
                    } else {
                        Text(event.startDate, style: .time)
                        Text("–")
                        Text(event.endDate, style: .time)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(event.calendarTitle, systemImage: event.feedId != nil ? "link" : "iphone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scheda dell'evento

struct DeviceCalendarEventSheet: View {

    let event: DeviceCalendarEvent
    let onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title)
                            .font(.title3.weight(.semibold))
                        whenText
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 10) {
                        Circle().fill(event.color).frame(width: 10, height: 10)
                        Text(event.calendarTitle)
                    }

                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                }

                Section {
                    Button {
                        onCopy()
                    } label: {
                        Label("Copia in KidBox", systemImage: "square.and.arrow.down.on.square")
                    }
                    #if !targetEnvironment(macCatalyst)
                    // Un calendario iscritto non ha un'app di sistema in cui aprirlo.
                    if event.feedId == nil {
                        Button {
                            DeviceCalendarStore.shared.openInSystemCalendar(event)
                        } label: {
                            Label("Apri in Calendario", systemImage: "calendar")
                        }
                    }
                    #endif
                } footer: {
                    if event.feedId != nil {
                        Text(String(format: String(localized: "Questo evento viene dal calendario iscritto «%@» e lo vede tutta la famiglia. Copiandolo in KidBox puoi aggiungere promemoria e visibilità; la copia non cambia se cambia il calendario."), event.calendarTitle))
                    } else {
                        Text("Questo evento viene dal calendario del tuo telefono e lo vedi solo tu. Copiandolo in KidBox lo vede la famiglia; la copia non cambia se modifichi l'originale.")
                    }
                }

                // Le note in fondo: un invito di Teams è lungo pagine, e prima
                // spingeva i pulsanti fuori dallo schermo.
                if let notes = event.notes {
                    Section("Note") {
                        Text(notes)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(event.feedId != nil ? "Calendario iscritto" : "Evento del telefono")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var whenText: some View {
        let cal = Calendar.current
        let sameDay = cal.isDate(event.startDate, inSameDayAs: event.endDate)
            // Un tutto-il-giorno di EventKit finisce alle 23:59:59 dello stesso giorno.
            || (event.isAllDay && cal.isDate(event.startDate, inSameDayAs: event.endDate.addingTimeInterval(-1)))
        if event.isAllDay {
            if sameDay {
                Text(event.startDate, format: .dateTime.weekday(.wide).day().month(.wide).year())
            } else {
                Text(verbatim: "\(event.startDate.formatted(.dateTime.day().month().year())) – \(event.endDate.formatted(.dateTime.day().month().year()))")
            }
        } else if sameDay {
            Text(verbatim: "\(event.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
        } else {
            Text(verbatim: "\(event.startDate.formatted(date: .abbreviated, time: .shortened)) – \(event.endDate.formatted(date: .abbreviated, time: .shortened))")
        }
    }
}

/// I due account proposti in «Collega un account».
enum ConnectProvider: Identifiable {
    case google, outlook
    var id: Self { self }

    var title: String {
        switch self {
        case .google:  return String(localized: "Collega Google Calendar")
        case .outlook: return String(localized: "Collega Outlook")
        }
    }

    var steps: String {
        switch self {
        case .google:
            return String(localized: "1. Apri Impostazioni › App › Calendario › Account di calendario.\n2. Tocca «Aggiungi account» › Google e accedi.\n3. Lascia attivo «Calendari».\n\nTorna in KidBox: i calendari di Google compaiono da soli.")
        case .outlook:
            return String(localized: "1. Apri Impostazioni › App › Calendario › Account di calendario.\n2. Tocca «Aggiungi account» › Outlook.com (o Microsoft Exchange per un account di lavoro) e accedi.\n3. Lascia attivo «Calendari».\n\nTorna in KidBox: i calendari di Outlook compaiono da soli.")
        }
    }
}

// MARK: - Iscrizione a un calendario da link

struct AddCalendarFeedView: View {
    let familyId: String

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var colorHex = CalendarFeedStore.palette[0]
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link del calendario (.ics o webcal://)", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Nome (facoltativo)", text: $name)
                } footer: {
                    Text("Il link di un calendario pubblicato: scuola, squadra, festività, o l'indirizzo iCal di un Google Calendar. Gli eventi li vede tutta la famiglia e si aggiornano da soli ogni qualche ora.")
                }

                Section {
                    DisclosureGroup("Come trovo il link?") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Google Calendar, dal computer: calendar.google.com › Impostazioni › scegli il calendario a sinistra › «Integra calendario» › copia «Indirizzo segreto in formato iCal».")
                            Text("Outlook, dal computer: outlook.com › Impostazioni › Calendario › Calendari condivisi › «Pubblica un calendario» › scegli il calendario e «Può visualizzare tutti i dettagli» › Pubblica › copia il link ICS.")
                            Text("Scuola, squadra o palestra: sul loro sito cerca «iCal», «ICS», «webcal» o «Aggiungi al calendario».")
                            Text("Il link lo vede tutta la famiglia: chi ce l'ha può leggere quel calendario.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(CalendarFeedStore.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .blue)
                                .frame(width: hex == colorHex ? 30 : 24, height: hex == colorHex ? 30 : 24)
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if isSaving {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Leggo il calendario…")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Iscriviti a un calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Iscriviti") { subscribe() }
                        .disabled(isSaving || url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// Il server scarica subito il link: se è sbagliato lo si sa adesso.
    private func subscribe() {
        isSaving = true
        errorMessage = nil
        Task {
            let outcome = await CalendarFeedStore.shared.subscribe(
                familyId: familyId,
                name: name.trimmingCharacters(in: .whitespaces),
                url: url.trimmingCharacters(in: .whitespaces),
                colorHex: colorHex
            )
            isSaving = false
            switch outcome {
            case .ok:
                dismiss()
            case .failed(let reason):
                errorMessage = CalendarFeedStore.message(for: reason)
            }
        }
    }
}
