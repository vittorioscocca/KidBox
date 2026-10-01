//
//  FamilyRequestViews.swift
//  KidBox
//
//  Le view delle richieste di famiglia:
//  - `FamilyRequestAskSheet`: a chi chiedere (dall'editor del to-do);
//  - `FamilyRequestSentSheet`: richiesta inviata, link per chi è fuori;
//  - `FamilyRequestsHomeSection`: le richieste aperte in Home;
//  - `FamilyRequestDetailSheet`: una richiesta, aperta da card o notifica.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth
internal import os

/// Richiesta da mostrare nel foglio di dettaglio (deep link, card).
struct FamilyRequestRef: Identifiable, Equatable {
    let familyId: String
    let requestId: String
    var id: String { "\(familyId)/\(requestId)" }
}

// MARK: - Nomi

/// Nomi dei membri per uid, come li mostra il resto dell'app.
private struct FamilyRequestNames {
    let members: [KBFamilyMember]
    let me: String?

    func name(_ uid: String) -> String {
        if uid == me { return String(localized: "Tu") }
        let m = members.first { $0.userId == uid }
        let name = (m?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "Un membro della famiglia") : name
    }

    func firstName(_ uid: String) -> String {
        let full = name(uid)
        return full.split(separator: " ").first.map(String.init) ?? full
    }
}

// MARK: - A chi chiedere

struct FamilyRequestAskSheet: View {
    @Binding var draft: FamilyRequestService.Draft?
    let members: [KBFamilyMember]
    /// Scadenza del to-do con il suo orario, o `nil`: serve a «chi è libero».
    let around: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var work = FamilyRequestService.Draft()
    @Query private var todos: [KBTodoItem]
    @Query private var events: [KBCalendarEvent]

    init(draft: Binding<FamilyRequestService.Draft?>, members: [KBFamilyMember], familyId: String, around: Date?) {
        _draft = draft
        self.members = members
        self.around = around
        let fid = familyId
        _todos = Query(filter: #Predicate<KBTodoItem> { $0.familyId == fid && !$0.isDeleted && !$0.isDone })
        _events = Query(filter: #Predicate<KBCalendarEvent> { $0.familyId == fid && !$0.isDeleted })
    }

    private var availability: FamilyRequestAvailability? {
        FamilyRequestAvailability.compute(
            around: around,
            todos: todos,
            events: events,
            currentUid: Auth.auth().currentUser?.uid
        )
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        let availability = availability
        NavigationStack {
            Form {
                // Contesto, non attribuito a nessuno: gli eventi non dicono chi
                // partecipa. Vedi `FamilyRequestAvailability`.
                if let availability, !availability.events.isEmpty {
                    Section {
                        ForEach(availability.events) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                if item.isAllDay {
                                    Text("Tutto il giorno")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(verbatim: "\(Self.time(item.start))–\(Self.time(item.end))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.title)
                            }
                        }
                    } header: {
                        Text("In calendario, intorno alle \(Self.time(availability.around))")
                    }
                }

                if members.isEmpty {
                    Section {
                        Text("Per ora in famiglia ci sei solo tu: chiedi a qualcuno fuori dall'app, con un link.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(members) { member in
                            Button {
                                toggle(member.userId)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName ?? String(localized: "Membro"))
                                            .foregroundStyle(.primary)
                                        if let first = availability?.busy[member.userId]?.first {
                                            Text("Ha già «\(first.title)» alle \(Self.time(first.start))")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Spacer()
                                    if work.recipients.contains(member.userId) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(KBTheme.bubbleTint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("In famiglia")
                    } footer: {
                        Text("Ricevono una notifica con «Ci penso io» e «Non posso».")
                    }
                }

                Section {
                    Toggle("Qualcuno fuori dall'app", isOn: $work.askOutside)
                    if work.askOutside {
                        TextField("Come lo chiami? (es. Nonna)", text: $work.outsideLabel)
                        Toggle("Includi l'invito alla famiglia", isOn: $work.includeInvite)
                    }
                } header: {
                    Text("Con un link")
                } footer: {
                    if work.askOutside {
                        if work.includeInvite {
                            Text("Risponde dal browser, senza installare nulla. Dopo può entrare in famiglia: il link vale come invito per 7 giorni e una volta sola.")
                        } else {
                            Text("Risponde dal browser, senza installare nulla.")
                        }
                    } else {
                        Text("Per i nonni, la babysitter o chi non ha KidBox: mandi il link su WhatsApp e risponde dal browser.")
                    }
                }
            }
            .navigationTitle("Chiedi a…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        draft = work
                        dismiss()
                    }
                    .disabled(work.isEmpty)
                }
            }
            .onAppear {
                if let draft { work = draft }
                if members.isEmpty { work.askOutside = true }
            }
        }
    }

    private func toggle(_ uid: String) {
        if let i = work.recipients.firstIndex(of: uid) {
            work.recipients.remove(at: i)
        } else {
            work.recipients.append(uid)
        }
    }
}

// MARK: - Richiesta inviata

struct FamilyRequestSentSheet: View {
    let created: FamilyRequestService.Created

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(KBTheme.bubbleTint)
                    .padding(.top, 8)

                Text("Richiesta inviata")
                    .font(.title2.weight(.bold))

                if created.notifiedCount > 0 {
                    Text("Abbiamo avvisato chi hai scelto in famiglia. Ora manda il link a chi non ha l'app.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ora manda il link a chi vuoi: risponde dal browser, senza installare nulla.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                if let text = created.shareText {
                    ShareLink(item: text) {
                        Label("Invia il link", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(KBTheme.bubbleTint, in: Capsule())
                    }

                    Button {
                        UIPasteboard.general.string = created.shareLink
                        copied = true
                    } label: {
                        // Un `Label` per ramo: il ternario fra due letterali
                        // diventa `String` e salterebbe il catalogo.
                        Group {
                            if copied {
                                Label("Copiato", systemImage: "checkmark")
                            } else {
                                Label("Copia il link", systemImage: "doc.on.doc")
                            }
                        }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(KBTheme.bubbleTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(KBTheme.bubbleTint.opacity(0.12), in: Capsule())
                    }
                }

                Text("Il to-do nasce quando qualcuno risponde «Ci penso io»: lo vedrete tutti.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Home

/// Le richieste aperte della famiglia, sopra le sezioni. Le ascolta la Home
/// (`FamilyRequestService.observeOpen`), così senza richieste la sezione non
/// c'è proprio e non lascia uno spazio vuoto.
struct FamilyRequestsHomeSection: View {
    let familyId: String
    let requests: [FamilyRequest]

    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var members: [KBFamilyMember]

    init(familyId: String, requests: [FamilyRequest]) {
        self.familyId = familyId
        self.requests = requests
        let fid = familyId
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted })
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(requests) { request in
                FamilyRequestCard(
                    request: request,
                    names: FamilyRequestNames(members: members, me: Auth.auth().currentUser?.uid),
                    open: {
                        coordinator.presentedFamilyRequest = FamilyRequestRef(familyId: familyId, requestId: request.id)
                    },
                    // Il banner globale e non un alert della card: dopo un
                    // «Ci penso io» la card sparisce, e l'alert con lei.
                    onMessage: { coordinator.globalBannerMessage = $0 }
                )
            }
        }
    }
}

private struct FamilyRequestCard: View {
    let request: FamilyRequest
    let names: FamilyRequestNames
    let open: () -> Void
    let onMessage: (String) -> Void

    @State private var busy = false

    private var isMine: Bool { request.createdBy == names.me }
    private var myAnswer: FamilyRequest.Response? { names.me.flatMap { request.response(of: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        if isMine {
                            Text("Hai chiesto")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(names.firstName(request.createdBy)) chiede")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(request.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if let due = request.dueAt {
                            Text(FamilyRequestService.whenText(due, hasTime: request.dueHasTime))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(KBTheme.bubbleTint)
                        }
                        if isMine {
                            Text(waitingSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if !isMine {
                HStack(spacing: 10) {
                    Button {
                        answer(yes: true)
                    } label: {
                        Text("Ci penso io")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(KBTheme.bubbleTint, in: Capsule())
                    }
                    Button {
                        answer(yes: false)
                    } label: {
                        Group {
                            if myAnswer?.isYes == false {
                                Text("Hai detto: non posso")
                            } else {
                                Text("Non posso")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(KBTheme.bubbleTint.opacity(0.12), in: Capsule())
                    }
                    .disabled(myAnswer?.isYes == false)
                }
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
    }

    /// «In attesa: Luca non può» — quel che sa chi ha chiesto.
    private var waitingSummary: String {
        let no = request.responses.filter { !$0.isYes }.map(\.name).filter { !$0.isEmpty }
        if no.isEmpty { return String(localized: "In attesa di una risposta") }
        return String(localized: "Non possono: \(no.joined(separator: ", "))")
    }

    private func answer(yes: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let outcome = try await FamilyRequestService.respond(
                    familyId: request.familyId, requestId: request.id, yes: yes
                )
                if let message = FamilyRequestCopy.message(for: outcome) { onMessage(message) }
            } catch {
                onMessage(String(localized: "Non riesco a inviare la risposta. Riprova tra poco."))
            }
        }
    }
}

/// Testi dell'esito di una risposta, condivisi da card e foglio.
enum FamilyRequestCopy {
    static func message(for outcome: FamilyRequestService.Outcome) -> String? {
        switch outcome {
        case .claimedByMe:
            return String(localized: "Fatto: è nei tuoi to-do, e in famiglia lo vedono tutti.")
        case .claimedBy(let name):
            if name.isEmpty { return String(localized: "Qualcuno ha risposto prima di te.") }
            return String(localized: "Ci pensa già \(name).")
        case .declined:
            return nil
        case .closed:
            return String(localized: "Questa richiesta non è più aperta.")
        }
    }
}

// MARK: - Dettaglio

struct FamilyRequestDetailSheet: View {
    let familyId: String
    let requestId: String

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [KBFamilyMember]

    @State private var request: FamilyRequest?
    @State private var loaded = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmCancel = false

    init(familyId: String, requestId: String) {
        self.familyId = familyId
        self.requestId = requestId
        let fid = familyId
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted })
    }

    private var names: FamilyRequestNames {
        FamilyRequestNames(members: members, me: Auth.auth().currentUser?.uid)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let request {
                    content(request)
                } else if loaded {
                    ContentUnavailableView(
                        "Richiesta non disponibile",
                        systemImage: "hand.raised.slash",
                        description: Text("Forse è stata ritirata, o non sei più in questa famiglia.")
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Richiesta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .task(id: requestId) {
            for await value in FamilyRequestService.observe(familyId: familyId, requestId: requestId) {
                request = value
                loaded = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func content(_ r: FamilyRequest) -> some View {
        let isMine = r.createdBy == names.me
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if isMine {
                        Text("Hai chiesto")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(names.firstName(r.createdBy)) chiede")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(r.title).font(.title3.weight(.bold))
                    if let due = r.dueAt {
                        Text(FamilyRequestService.whenText(due, hasTime: r.dueHasTime))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(KBTheme.bubbleTint)
                    }
                    if let notes = r.notes {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                statusRow(r)
                ForEach(r.responses.filter { !$0.isYes }, id: \.key) { resp in
                    HStack {
                        if resp.isExternal {
                            Text("\(resp.name) (dal link)")
                        } else {
                            Text(resp.key == names.me ? String(localized: "Tu") : resp.name)
                        }
                        Spacer()
                        Text("Non può").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Risposte")
            }

            if let message {
                Section { Text(message) }
            }

            actions(r, isMine: isMine)
        }
        .confirmationDialog("Ritirare la richiesta?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Ritira", role: .destructive) { cancel(r) }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Chi l'ha ricevuta non potrà più rispondere, nemmeno dal link.")
        }
    }

    @ViewBuilder
    private func statusRow(_ r: FamilyRequest) -> some View {
        switch r.status {
        case .claimed:
            if r.claimedByUid == names.me {
                Label("Ci pensi tu", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(KBTheme.green)
            } else if r.claimedByExternal {
                Label("Ci pensa \(r.claimedByName ?? "") (dal link)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(KBTheme.green)
            } else {
                Label("Ci pensa \(r.claimedByUid.map(names.name) ?? (r.claimedByName ?? ""))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(KBTheme.green)
            }
        case .expired:
            Label("Scaduta: nessuno ha risposto", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .cancelled:
            Label("Richiesta ritirata", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .open:
            if r.isOpen {
                Label("In attesa di una risposta", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else {
                Label("Scaduta: nessuno ha risposto", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actions(_ r: FamilyRequest, isMine: Bool) -> some View {
        if r.isOpen && !isMine {
            Section {
                Button {
                    respond(r, yes: true)
                } label: {
                    Label("Ci penso io", systemImage: "hand.raised.fill")
                }
                Button {
                    respond(r, yes: false)
                } label: {
                    Label("Non posso", systemImage: "hand.raised.slash")
                }
                .disabled(names.me.flatMap { r.response(of: $0) }?.isYes == false)
            }
            .disabled(busy)
        }
        if r.isOpen && isMine {
            Section {
                if r.hasExternalLink, let link = FamilyRequestService.savedShareLink(requestId: r.id) {
                    ShareLink(item: FamilyRequestService.shareText(
                        title: r.title, dueAt: r.dueAt, dueHasTime: r.dueHasTime, link: link
                    )) {
                        Label("Invia di nuovo il link", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) {
                    confirmCancel = true
                } label: {
                    Label("Ritira la richiesta", systemImage: "xmark.circle")
                }
            }
            .disabled(busy)
        }
        if r.status == .claimed, let todoId = r.todoId, !r.listId.isEmpty {
            Section {
                Button {
                    openTodo(r, todoId: todoId)
                } label: {
                    Label("Apri il to-do", systemImage: "checklist")
                }
            }
        }
    }

    private func respond(_ r: FamilyRequest, yes: Bool) {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let outcome = try await FamilyRequestService.respond(familyId: r.familyId, requestId: r.id, yes: yes)
                message = FamilyRequestCopy.message(for: outcome)
            } catch {
                message = String(localized: "Non riesco a inviare la risposta. Riprova tra poco.")
            }
        }
    }

    private func cancel(_ r: FamilyRequest) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await FamilyRequestService.cancel(familyId: r.familyId, requestId: r.id)
            } catch {
                message = String(localized: "Non riesco a ritirarla: forse qualcuno l'ha appena presa.")
            }
        }
    }

    private func openTodo(_ r: FamilyRequest, todoId: String) {
        dismiss()
        // Si naviga a foglio chiuso: un `path.append` durante l'animazione di
        // chiusura può essere scartato dal NavigationStack.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            coordinator.openTodoFromPush(
                familyId: r.familyId,
                childId: r.childId,
                listId: r.listId,
                todoId: todoId,
                modelContext: modelContext
            )
        }
    }
}
