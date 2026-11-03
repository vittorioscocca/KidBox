//
//  CalendarExportView.swift
//  KidBox
//
//  Il calendario di KidBox dentro Google Calendar, Outlook e il Calendario di
//  Apple: un link iCal personale (functions/calendarExport.js) a cui quei
//  calendari si iscrivono. Personale e non di famiglia perché rispetta la
//  visibilità degli eventi. Sola lettura, e Google lo rilegge quando vuole lui
//  (12-24 ore): il testo lo dice, se no sembra rotto. Gemello di
//  `CalendarExportModal.jsx` della web app.
//

import SwiftUI
import UIKit
import Combine
import FirebaseFunctions

@MainActor
final class CalendarExportStore: ObservableObject {

    @Published private(set) var url: URL?
    @Published private(set) var isLoading = true
    @Published private(set) var isBusy = false
    @Published var failed = false

    private let functions = Functions.functions(region: "europe-west1")

    /// «get» non crea niente; «enable» crea se manca; «rotate» sostituisce il
    /// link (il vecchio muore subito); «disable» lo spegne.
    func run(_ action: String, familyId: String) async {
        if action == "get" { isLoading = true } else { isBusy = true }
        defer { isLoading = false; isBusy = false }
        do {
            let result = try await functions.httpsCallable("calendarExportLink").call([
                "familyId": familyId,
                "action": action,
                "tz": TimeZone.current.identifier,
            ])
            let raw = (result.data as? [String: Any])?["url"] as? String
            url = raw.flatMap(URL.init(string:))
            failed = false
        } catch {
            KBLog.calendar.kbError("CalendarExportStore: \(action) fallita \(error.localizedDescription)")
            failed = true
        }
    }

    /// Il Calendario di Apple si iscrive da solo aprendo `webcal://`.
    var webcalURL: URL? {
        url.flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "https://", with: "webcal://")) }
    }

    var googleURL: URL? {
        guard let webcal = webcalURL?.absoluteString,
              let enc = webcal.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "https://calendar.google.com/calendar/r?cid=\(enc)")
    }

    func outlookURL(work: Bool) -> URL? {
        guard let enc = url?.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        let host = work ? "outlook.office.com" : "outlook.live.com"
        return URL(string: "https://\(host)/calendar/0/addfromweb?url=\(enc)&name=KidBox")
    }
}

struct CalendarExportView: View {

    let familyId: String

    @StateObject private var store = CalendarExportStore()
    @Environment(\.openURL) private var openURL
    @State private var confirmRotate = false
    @State private var confirmDisable = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                EmptyView()
            } footer: {
                Text("Un link solo tuo: Google Calendar, Outlook o il Calendario di Apple lo leggono e mostrano gli eventi di famiglia che vedi tu. È in sola lettura: gli eventi si creano e si cambiano in KidBox.")
            }

            if store.isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if store.url == nil {
                Section {
                    Button {
                        Task { await store.run("enable", familyId: familyId) }
                    } label: {
                        HStack {
                            Label("Crea il mio link", systemImage: "link.badge.plus")
                            Spacer()
                            if store.isBusy { ProgressView() }
                        }
                    }
                    .disabled(store.isBusy)
                } footer: {
                    notes
                }
            } else {
                Section {
                    linkButton("Aggiungi al Calendario dell'iPhone", systemImage: "calendar.badge.plus", url: store.webcalURL)
                    linkButton("Aggiungi a Google Calendar", systemImage: "g.circle", url: store.googleURL)
                    linkButton("Aggiungi a Outlook.com", systemImage: "envelope", url: store.outlookURL(work: false))
                    linkButton("Outlook di lavoro (Microsoft 365)", systemImage: "briefcase", url: store.outlookURL(work: true))
                    Button {
                        UIPasteboard.general.string = store.url?.absoluteString
                        copied = true
                    } label: {
                        if copied {
                            Label("Copiato", systemImage: "checkmark")
                        } else {
                            Label("Copia il link", systemImage: "doc.on.doc")
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Se Google Calendar non si apre dal telefono, aggiungilo dal computer: calendar.google.com › Altri calendari › + › Da URL, e incolla il link.")
                        notes
                    }
                }

                Section {
                    Button("Rigenera il link") { confirmRotate = true }
                        .disabled(store.isBusy)
                    Button("Disattiva", role: .destructive) { confirmDisable = true }
                        .disabled(store.isBusy)
                }
            }
        }
        .navigationTitle("Google, Outlook e Apple")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.run("get", familyId: familyId) }
        .confirmationDialog("Rigenera il link", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("Rigenera il link", role: .destructive) {
                copied = false
                Task { await store.run("rotate", familyId: familyId) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il link attuale smetterà subito di funzionare: andrà aggiunto di nuovo in Google o Outlook.")
        }
        .confirmationDialog("Disattiva", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disattiva", role: .destructive) {
                copied = false
                Task { await store.run("disable", familyId: familyId) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il link smetterà di funzionare e gli eventi spariranno da Google o Outlook al prossimo aggiornamento.")
        }
        .alert("Non è stato possibile completare l'operazione. Riprova.", isPresented: $store.failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google rilegge i calendari iscritti quando vuole lui, di solito ogni 12-24 ore: un evento nuovo può comparire lì il giorno dopo. Outlook e Apple sono più rapidi.")
            Text("Chi ha questo link vede i tuoi eventi di famiglia. Se l'hai condiviso per sbaglio, rigeneralo: il vecchio smette subito di funzionare.")
        }
    }

    private func linkButton(_ title: LocalizedStringKey, systemImage: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(url == nil || store.isBusy)
    }
}
