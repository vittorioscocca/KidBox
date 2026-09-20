//
//  WalletTicketDetailView.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth

struct WalletTicketDetailView: View {
    let familyId: String
    let ticketId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var reminderDenied = false
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var tickets: [KBWalletTicket]
    @Query private var members: [KBFamilyMember]

    @State private var isLoadingPDF = false
    @State private var pdfData: Data?
    @State private var pdfError: String?
    @State private var showPDF = false
    /// Copia in chiaro del PDF su disco, creata solo per la condivisione.
    /// Il PDF vive cifrato su Storage e decifrato in memoria: per passarlo a
    /// un'altra app serve un file vero, e serve che si chiami come l'originale
    /// — condividere `UUID.pdf` rende irriconoscibile l'allegato a chi lo
    /// riceve. Si cancella alla chiusura del visore.
    @State private var sharePDFURL: URL?
    @State private var isVisibilitySheetPresented = false
    @State private var showVisibilityLockedAlert = false
    @State private var visibilitySheetScope = KBVisibilityScope.onlyCreator
    @State private var visibilitySheetMemberIds: Set<String> = []

    private let pdfStore = WalletPDFStore()

    init(familyId: String, ticketId: String) {
        self.familyId = familyId
        self.ticketId = ticketId
        _tickets = Query(filter: #Predicate<KBWalletTicket> { $0.id == ticketId && $0.isDeleted == false })
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }

    private var ticket: KBWalletTicket? { tickets.first }

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var selectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }

    private func canEditVisibility(for ticket: KBWalletTicket) -> Bool {
        guard let uid = currentUid else { return false }
        let cid = ticket.createdBy.trimmingCharacters(in: .whitespacesAndNewlines)
        if cid.isEmpty { return true }
        return cid == uid
    }

    var body: some View {
        Group {
            if let ticket {
                if ticket.isVisible(to: currentUid) {
                    ticketDetailScroll(ticket)
                } else {
                    ContentUnavailableView(
                        "Biglietto non disponibile",
                        systemImage: "eye.slash",
                        description: Text("Non hai accesso a questo biglietto.")
                    )
                }
            } else {
                missingTicketPlaceholder
            }
        }
        .navigationTitle("Dettaglio biglietto")
        .navigationBarTitleDisplayMode(.inline)
        // Aprire il dettaglio è il recupero vero: è per questo che il biglietto
        // è stato caricato. Non produce scritture, quindi il server non lo vede.
        .onAppear {
            guard let ticket, ticket.isVisible(to: currentUid) else { return }
            let origin = coordinator.consumeRetrievalOrigin()
            Task {
                await KBAnalytics.shared.logRetrieval(
                    feature: .wallet,
                    uploaderUid: ticket.createdBy,
                    createdAt: ticket.createdAt,
                    entryPoint: origin
                )
            }
            if ticket.createdBy != currentUid {
                AppAnalytics.contentSharedRead(type: "wallet")
            }
        }
        .fullScreenCover(isPresented: $showPDF) {
            NavigationStack {
                Group {
                    if let pdfData {
                        WalletPDFViewer(pdfData: pdfData)
                    } else {
                        Text("Nessun PDF disponibile")
                            .padding()
                    }
                }
                .navigationTitle("Biglietto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Chiudi") { showPDF = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let sharePDFURL {
                            ShareLink(item: sharePDFURL) {
                                Label("Condividi", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .task(id: pdfData) { prepareShareFile() }
            }
            .allowsAllOrientationsWhileVisible()
            .onDisappear { discardShareFile() }
        }
        .overlay {
            if isLoadingPDF {
                ProgressView("Caricamento PDF...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .alert("Errore PDF", isPresented: Binding(
            get: { pdfError != nil },
            set: { if !$0 { pdfError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfError ?? "")
        }
        .sheet(isPresented: $isVisibilitySheetPresented) {
            VisibilityPickerSheet(
                selectedScope: $visibilitySheetScope,
                selectedMemberIds: $visibilitySheetMemberIds,
                members: selectableMembers,
                currentUid: currentUid,
                scopeSectionTitle: "Chi può vedere questo biglietto"
            ) { scope, memberIds in
                guard let t = tickets.first else { return }
                applyWalletVisibility(ticket: t, scope: scope, memberIds: memberIds)
                isVisibilitySheetPresented = false
            }
        }
        .alert("Visibilità bloccata", isPresented: $showVisibilityLockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Solo chi ha creato il biglietto può modificare la visibilità.")
        }
    }

    private var missingTicketPlaceholder: some View {
        ContentUnavailableView(
            "Biglietto non trovato",
            systemImage: "ticket.slash",
            description: Text("Potrebbe essere stato eliminato o non ancora sincronizzato.")
        )
    }

    @ViewBuilder
    private func ticketDetailScroll(_ ticket: KBWalletTicket) -> some View {
        ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        walletVisibilityChip(for: ticket)

                        // Header card — stesso componente della home, altezza
                        // un filo maggiore per dare respiro.
                        WalletTicketCardView(ticket: ticket, height: 210)

                        // Codice visivo (QR/Aztec/PDF417/Code128/…).
                        if let barcode = ticket.extractedBarcodeText, !barcode.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Codice di accesso")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                WalletBarcodeView(
                                    text: barcode,
                                    format: ticket.extractedBarcodeFormat
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .padding(16)
                            .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
                            )
                        }

                        detailsBlock(for: ticket)
                        reminderBlock(for: ticket)
                        actionsBlock(for: ticket)
                        destructiveBlock(for: ticket)
                    }
                    .padding(16)
                }
                .background(KBTheme.background(colorScheme).ignoresSafeArea())
    }

    private func walletVisibilityChip(for ticket: KBWalletTicket) -> some View {
        Button {
            if canEditVisibility(for: ticket) {
                visibilitySheetScope = KBWalletTicket.normalizedVisibilityScopeForWallet(ticket.visibilityScope)
                visibilitySheetMemberIds = Set(ticket.visibilityMemberIds ?? [])
                isVisibilitySheetPresented = true
            } else {
                showVisibilityLockedAlert = true
            }
        } label: {
            HStack {
                Text(KBVisibilityScope.chipLabel(for: KBWalletTicket.normalizedVisibilityScopeForWallet(ticket.visibilityScope)))
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.949, green: 0.941, blue: 0.922))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyWalletVisibility(ticket: KBWalletTicket, scope: String, memberIds: Set<String>) {
        let normalizedScope = KBWalletTicket.normalizedVisibilityScopeForWallet(scope)
        ticket.visibilityScope = normalizedScope
        ticket.visibilityMemberIds = normalizedScope == KBVisibilityScope.members
            ? Array(memberIds).sorted()
            : []
        if let uid = Auth.auth().currentUser?.uid {
            ticket.updatedBy = uid
            ticket.updatedByName = Auth.auth().currentUser?.displayName ?? ""
        }
        ticket.updatedAt = .now
        ticket.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueWalletTicketUpsert(
            ticketId: ticket.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    // MARK: - Blocks

    @ViewBuilder
    private func detailsBlock(for ticket: KBWalletTicket) -> some View {
        let hasLocation = (ticket.location?.isEmpty == false)
        let hasArrivalLocation = (ticket.arrivalLocation?.isEmpty == false)
        let hasHolderName = (ticket.holderName?.isEmpty == false)
        let hasBooking = (ticket.bookingCode?.isEmpty == false)
        let hasSeat = (ticket.seat?.isEmpty == false)
        let hasPrice = (ticket.price?.isEmpty == false)
        let hasNotes = (ticket.notes?.isEmpty == false)

        if hasLocation || hasArrivalLocation || hasHolderName || hasBooking || hasSeat || hasPrice || hasNotes ||
            ticket.eventDate != nil || ticket.eventEndDate != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dettagli")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let holderName = ticket.holderName, !holderName.isEmpty {
                    detailRow(icon: "person.fill", title: "Titolare", value: holderName)
                }
                if let eventDate = ticket.eventDate {
                    detailRow(
                        icon: "calendar",
                        title: "Partenza",
                        value: localizedTicketDateTime(eventDate)
                    )
                }
                if let location = ticket.location, !location.isEmpty {
                    detailRow(icon: "mappin.and.ellipse", title: "Luogo di partenza", value: location)
                }
                if let eventEndDate = ticket.eventEndDate {
                    detailRow(
                        icon: "calendar",
                        title: "Arrivo",
                        value: localizedTicketDateTime(eventEndDate)
                    )
                }
                if let arrivalLocation = ticket.arrivalLocation, !arrivalLocation.isEmpty {
                    detailRow(icon: "mappin.and.ellipse", title: "Luogo di arrivo", value: arrivalLocation)
                }
                // Sta fra il luogo e il codice perché è così che si legge un
                // biglietto: dove si va, dove ci si siede, e poi il numero da
                // esibire. Il campo esisteva già sul modello ma non lo
                // riempiva nessuno, quindi questa riga non compariva mai.
                if let seat = ticket.seat, !seat.isEmpty {
                    detailRow(icon: "chair.fill", title: "Posto", value: seat)
                }
                if let price = ticket.price, !price.isEmpty {
                    detailRow(icon: "eurosign.circle", title: "Prezzo", value: price)
                }
                if let bookingCode = ticket.bookingCode, !bookingCode.isEmpty {
                    detailRow(icon: "number", title: "Codice biglietto", value: bookingCode, monospaced: true)
                }
                if let notes = ticket.notes, !notes.isEmpty {
                    detailRow(icon: "note.text", title: "Note", value: notes)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    /// Opzioni del picker promemoria. `nil` = legacy (default per categoria),
    /// coerente con `WalletReminderService.scheduleReminders(for:)`.
    private static let reminderOptions: [(label: String, hours: Int?)] = [
        (NSLocalizedString("Predefinito", comment: "Wallet ticket reminder: default per category"), nil),
        (NSLocalizedString("Nessuno", comment: "Wallet ticket reminder: none"), 0),
        (NSLocalizedString("1 ora prima", comment: "Wallet ticket reminder: 1 hour before"), 1),
        (NSLocalizedString("1 giorno prima", comment: "Wallet ticket reminder: 1 day before"), 24),
        (NSLocalizedString("2 giorni prima", comment: "Wallet ticket reminder: 2 days before"), 48)
    ]

    @ViewBuilder
    private func reminderBlock(for ticket: KBWalletTicket) -> some View {
        // Solo se c'è una data evento: senza `eventDate` non c'è nulla da schedulare.
        if ticket.eventDate != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Promemoria")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Promemoria", selection: Binding(
                    get: { ticket.reminderOffsetHours },
                    set: { newValue in applyReminderOffset(ticket: ticket, hours: newValue) }
                )) {
                    ForEach(Self.reminderOptions, id: \.hours) { option in
                        Text(option.label).tag(option.hours)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if reminderDenied {
                    KBNotificationsDisabledCard()
                }
            }
            .task {
                // Promemoria attivo (tutto tranne «Nessuno») ma notifiche bloccate:
                // l'avviso compare subito, il biglietto proverà ad avvisare e non potrà.
                if ticket.reminderOffsetHours != 0 {
                    reminderDenied = !(await KBReminderPermission.isGranted())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { @MainActor in
                    if await KBReminderPermission.isGranted() { reminderDenied = false }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private func applyReminderOffset(ticket: KBWalletTicket, hours: Int?) {
        // «Nessuno» (0) è sempre libero; ogni altra scelta, compreso il
        // «Predefinito» (nil), arma una notifica e passa dal permesso: se
        // negato la tendina resta com'era e compare l'avviso.
        guard hours == 0 else {
            Task { @MainActor in
                let ok = await KBReminderPermission.requestIfNeeded()
                reminderDenied = !ok
                if ok { commitReminderOffset(ticket: ticket, hours: hours) }
            }
            return
        }
        reminderDenied = false
        commitReminderOffset(ticket: ticket, hours: 0)
    }

    private func commitReminderOffset(ticket: KBWalletTicket, hours: Int?) {
        ticket.reminderOffsetHours = hours
        if let uid = Auth.auth().currentUser?.uid {
            ticket.updatedBy = uid
            ticket.updatedByName = Auth.auth().currentUser?.displayName ?? ""
        }
        ticket.updatedAt = .now
        ticket.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueWalletTicketUpsert(
            ticketId: ticket.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        Task { await WalletReminderService.shared.scheduleReminders(for: ticket) }
    }

    private func detailRow(icon: String, title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func actionsBlock(for ticket: KBWalletTicket) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await openPDF() }
            } label: {
                Label("Apri PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoadingPDF)

            if let url = ticket.addToAppleWalletURL,
               let parsed = URL(string: url) {
                Button {
                    UIApplication.shared.open(parsed)
                } label: {
                    Label("Aggiungi ad Apple Wallet", systemImage: "wallet.pass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func destructiveBlock(for ticket: KBWalletTicket) -> some View {
        Button(role: .destructive) {
            deleteTicket(ticket)
        } label: {
            Label("Elimina biglietto", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
        .padding(.top, 4)
    }

    // MARK: - PDF / Delete

    /// Scrive la copia condivisibile. Il nome è quello del file originale,
    /// dentro una cartella con un id casuale: due biglietti diversi possono
    /// chiamarsi entrambi `biglietto.pdf`, e senza la cartella il secondo
    /// sovrascriverebbe il primo mentre il primo è ancora aperto.
    private func prepareShareFile() {
        discardShareFile()
        guard let pdfData else { return }
        let name = ticket?.pdfFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (name?.isEmpty == false ? name! : "Biglietto.pdf")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallet-share-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(fileName)
            try pdfData.write(to: url, options: .atomic)
            sharePDFURL = url
        } catch {
            // Senza copia niente pulsante: il visore continua a funzionare, e
            // un errore modale qui interromperebbe la lettura del biglietto
            // per una funzione accessoria.
            sharePDFURL = nil
        }
    }

    /// Il PDF è un documento personale: la copia in chiaro non deve
    /// sopravvivere alla schermata che l'ha creata.
    private func discardShareFile() {
        guard let sharePDFURL else { return }
        try? FileManager.default.removeItem(at: sharePDFURL.deletingLastPathComponent())
        self.sharePDFURL = nil
    }

    private func openPDF() async {
        guard let ticket else { return }
        isLoadingPDF = true
        defer { isLoadingPDF = false }
        do {
            let data = try await pdfStore.download(familyId: familyId, ticketId: ticket.id)
            pdfData = data
            showPDF = true
        } catch {
            pdfError = error.localizedDescription
        }
    }

    private func deleteTicket(_ ticket: KBWalletTicket) {
        ticket.isDeleted = true
        ticket.updatedAt = .now
        ticket.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueWalletTicketDelete(
            ticketId: ticket.id,
            familyId: familyId,
            modelContext: modelContext
        )
        // Flush immediato per propagare il soft-delete a Firestore / altri membri
        // subito, senza attendere il prossimo scene .active.
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        Task {
            await WalletReminderService.shared.cancelReminders(ticketId: ticket.id)
        }
        dismiss()
    }

    private func localizedTicketDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.calendar = kbDeviceCalendar()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
