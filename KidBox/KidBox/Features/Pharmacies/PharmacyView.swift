//
//  PharmacyView.swift
//  KidBox
//
//  Farmacie di turno (Pro e Max). Tre cose che la schermata non deve mai fare:
//  mostrare un elenco che potrebbe essere di ieri (se la fonte è ferma resta il
//  link), presentare come ufficiale una fonte incerta (la riga della fonte dice
//  sempre di chi è il dato), togliere all'utente la possibilità di indicare a
//  mano il sito («Usa un altro sito» c'è in ogni stato).
//  Disegno: internal/farmacie-di-turno.md.
//

import SwiftUI
import Combine

@MainActor
final class PharmacyViewModel: ObservableObject {

    @Published var feed: PharmacyFeed?
    @Published var isLoading = false
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var notice: String?

    func load(familyId: String, place: NewsPlace) async {
        isLoading = feed == nil
        defer { isLoading = false }
        do {
            feed = try await PharmacyService.shared.fetch(familyId: familyId, place: place)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func find(familyId: String, place: NewsPlace) async {
        guard !isWorking else { return }
        isWorking = true
        notice = nil
        defer { isWorking = false }
        do {
            let status = try await PharmacyService.shared.findSource(familyId: familyId, place: place)
            if status == "not-found" {
                notice = NSLocalizedString("Non ho trovato una pagina ufficiale per questo comune. Puoi indicare tu il sito.", comment: "Pharmacies: AI found nothing")
            }
            errorMessage = nil
            feed = try await PharmacyService.shared.fetch(familyId: familyId, place: place)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ritorna `true` se la scelta è stata registrata (anche quando il sito non si sa leggere).
    func setSource(familyId: String, place: NewsPlace, url: String?) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        notice = nil
        defer { isWorking = false }
        do {
            let status = try await PharmacyService.shared.setSource(familyId: familyId, place: place, url: url)
            if status == "unreadable" {
                notice = NSLocalizedString("Non riesco a leggere i turni da questo sito: resta il link per aprirlo.", comment: "Pharmacies: manual site unreadable")
            }
            errorMessage = nil
            feed = try await PharmacyService.shared.fetch(familyId: familyId, place: place)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct PharmacyView: View {

    let familyId: String

    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var familyStore = NewsFamilyStore.shared
    @StateObject private var vm = PharmacyViewModel()

    @State private var showUpgrade = false
    @State private var showOwnerOnly = false
    @State private var showSiteSheet = false
    @State private var showPlaceSettings = false
    @State private var siteText = ""

    private let tint = Color(red: 0.2, green: 0.66, blue: 0.5)

    private var family: NewsFamilySettings {
        familyStore.familyId == familyId ? familyStore.settings : NewsFamilySettings()
    }
    private var place: NewsPlace { family.effectivePlace }
    private var loadKey: String { "\(familyId)|\(place.label)|\(subscriptionManager.currentPlan == .free)" }

    var body: some View {
        Group {
            if subscriptionManager.currentPlan == .free {
                lockedView
            } else {
                content
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Farmacie di turno")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(triggerFeature: "pharmacies")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .ownerOnlyAlert(isPresented: $showOwnerOnly)
        .sheet(isPresented: $showSiteSheet) { siteSheet }
        .sheet(isPresented: $showPlaceSettings) {
            NavigationStack {
                NewsSettingsView(familyId: familyId)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fine") { showPlaceSettings = false }
                        }
                    }
            }
        }
        .task(id: familyId) { familyStore.bind(familyId: familyId) }
        .task(id: loadKey) {
            guard subscriptionManager.currentPlan != .free, familyStore.familyId == familyId, familyStore.isLoaded else { return }
            await vm.load(familyId: familyId, place: place)
        }
        .refreshable {
            guard subscriptionManager.currentPlan != .free else { return }
            await vm.load(familyId: familyId, place: place)
        }
    }

    // MARK: - Free

    private var lockedView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(tint)
                    .padding(.top, 24)
                Text("Farmacie di turno vicino a te")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Le farmacie di turno del tuo comune, lette dalla fonte ufficiale e aggiornate ogni giorno. Incluse nei piani Pro e Max.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    if subscriptionManager.isFamilyOwner {
                        showUpgrade = true
                        AppAnalytics.aiPaywallShown(context: "pharmacies")
                    } else {
                        showOwnerOnly = true
                    }
                } label: {
                    Text("Scopri Pro")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Contenuto

    @ViewBuilder
    private var content: some View {
        if !(familyStore.familyId == familyId && familyStore.isLoaded) || (vm.isLoading && vm.feed == nil) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    placeRow
                    if let message = vm.errorMessage { banner(message, symbol: "exclamationmark.triangle.fill", color: .orange) }
                    if let notice = vm.notice { banner(notice, symbol: "info.circle.fill", color: .blue) }
                    if let feed = vm.feed { feedBody(feed) }
                    emergencyNote
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .overlay { if vm.isWorking { workingOverlay } }
        }
    }

    private var placeRow: some View {
        Button { showPlaceSettings = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(tint)
                Text(place.hasCity ? place.label : String(localized: "Imposta il comune"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Cambia").font(.footnote).foregroundStyle(tint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(KBTheme.cardBackground(colorScheme)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func feedBody(_ feed: PharmacyFeed) -> some View {
        switch feed.status {
        case "ready":
            shiftsBody(feed)
            sourceFooter(feed)
        case "stale":
            infoCard(
                symbol: "clock.badge.exclamationmark",
                title: "Nessun turno aggiornato per oggi",
                text: "La fonte non ha ancora pubblicato i turni di oggi, quindi non li mostro per non darti un elenco vecchio. Apri il sito per controllare.",
                feed: feed
            )
        case "unreadable":
            infoCard(
                symbol: "doc.text.magnifyingglass",
                title: "Non riesco a leggere questo sito",
                text: "Ho trovato la pagina, ma non sono in grado di estrarne i turni in modo affidabile. Puoi aprirla qui sotto.",
                feed: feed
            )
        case "none":
            noneCard(feed)
        case "no-place":
            infoCard(symbol: "mappin.slash", title: "Manca il comune", text: "Imposta il comune della famiglia per vedere le farmacie di turno.", feed: nil)
        case "unsupported":
            infoCard(symbol: "globe.europe.africa.fill", title: "Per ora solo in Italia", text: "Le farmacie di turno sono disponibili per i comuni italiani.", feed: nil)
        default:
            EmptyView()
        }
    }

    // MARK: - Turni

    @ViewBuilder
    private func shiftsBody(_ feed: PharmacyFeed) -> some View {
        let today = feed.today ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("Di turno oggi").font(.headline)
            if today.isEmpty {
                Text("Oggi nessuna farmacia di turno in questo comune. Qui sotto trovi quelle dei comuni vicini.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(today) { shiftRow($0) }
            }
        }
        if let upcoming = feed.upcoming, !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nei prossimi giorni").font(.headline)
                ForEach(upcoming) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.dayLabel(day.date)).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                        ForEach(day.items) { shiftRow($0) }
                    }
                }
            }
        }
        if let others = feed.others, !others.isEmpty {
            DisclosureGroup {
                VStack(spacing: 10) { ForEach(others) { shiftRow($0, showComune: true) } }
                    .padding(.top, 8)
            } label: {
                Text("Di turno oggi nei comuni vicini").font(.headline)
            }
        }
    }

    private func shiftRow(_ s: PharmacyShift, showComune: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let service = s.serviceLabel {
                Text(service).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            Text(s.name).font(.subheadline.bold())
            if !s.address.isEmpty || !s.comune.isEmpty {
                Text([s.address, showComune || place.city.isEmpty ? s.comune : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if !s.dialNumber.isEmpty, let tel = URL(string: "tel:\(s.dialNumber)") {
                    Button { openURL(tel) } label: { Label("Chiama", systemImage: "phone.fill") }
                }
                if let q = s.mapQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let maps = URL(string: "https://maps.apple.com/?q=\(q)") {
                    Button { openURL(maps) } label: { Label("Indicazioni", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(KBTheme.cardBackground(colorScheme)))
    }

    // MARK: - Fonte

    private func sourceFooter(_ feed: PharmacyFeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = feed.source {
                HStack(spacing: 6) {
                    Image(systemName: Self.confidenceSymbol(source.confidence))
                    Text(Self.confidenceText(source.confidence)).font(.footnote.weight(.semibold))
                }
                .foregroundStyle(source.confidence == "uncertain" ? Color.orange : tint)
                HStack(spacing: 4) {
                    if let link = source.link {
                        Button { openURL(link) } label: { Text(source.label).underline() }.buttonStyle(.plain)
                    } else {
                        Text(source.label)
                    }
                    if let at = source.fetchedAt {
                        Text("· aggiornato alle \(at.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
                if source.confidence == "uncertain" {
                    Text("Questa fonte non è ufficiale o non sono sicuro che sia quella giusta: verifica con una telefonata.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Text("I turni possono cambiare: in caso di dubbio chiama la farmacia o guarda il cartello esposto.")
                .font(.footnote).foregroundStyle(.secondary)
            siteButtons(feed.source)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func siteButtons(_ source: PharmacySource?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                siteText = source?.manual == true ? (source?.url ?? "") : ""
                showSiteSheet = true
            } label: { Label("Usa un altro sito", systemImage: "link") }
            if source?.hasManual == true {
                Button {
                    Task { _ = await vm.setSource(familyId: familyId, place: place, url: nil) }
                } label: { Label("Torna alla fonte automatica", systemImage: "arrow.uturn.backward") }
            }
        }
        .font(.footnote.weight(.semibold))
        .tint(tint)
    }

    // MARK: - Altri stati

    private func noneCard(_ feed: PharmacyFeed) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Non ho ancora una fonte per questo comune", systemImage: "magnifyingglass")
                .font(.headline)
            Text("Posso cercare con l'AI la pagina ufficiale che pubblica i turni (Federfarma, Ordine dei farmacisti, ASL o Comune) e imparare a leggerla. Poi si aggiorna da sola, senza altri messaggi.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                Task { await vm.find(familyId: familyId, place: place) }
            } label: {
                Text(String(format: NSLocalizedString("Cerca la fonte (circa %d messaggi AI)", comment: "Pharmacies: find source button with AI cost"), feed.estimate?.find ?? 0))
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 12).fill(tint))
            }
            .buttonStyle(.plain)
            siteButtons(nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.cardBackground(colorScheme)))
    }

    private func infoCard(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey, feed: PharmacyFeed?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            if let source = feed?.source {
                if let link = source.link {
                    Button { openURL(link) } label: { Label("Apri \(source.label)", systemImage: "safari") }
                        .buttonStyle(.bordered).tint(tint)
                }
                Text(Self.confidenceText(source.confidence)).font(.footnote).foregroundStyle(.secondary)
                siteButtons(source)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.cardBackground(colorScheme)))
    }

    private var emergencyNote: some View {
        Text("Per un'urgenza medica chiama il 112.")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        Label { Text(text).font(.footnote) } icon: { Image(systemName: symbol).foregroundStyle(color) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text("Sto lavorando…").font(.footnote)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        }
    }

    // MARK: - Sito a mano

    private var siteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("", text: $siteText, prompt: Text(verbatim: "https://…"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text("Incolla l'indirizzo della pagina che mostra le farmacie di turno del tuo comune. Vale solo per la tua famiglia e ha la precedenza sulla fonte automatica. Se il sito non è già conosciuto, leggerlo costa circa \(vm.feed?.estimate?.manual ?? 0) messaggi AI, una volta sola.")
                }
            }
            .navigationTitle("Usa un altro sito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { showSiteSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usa") {
                        let text = siteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        showSiteSheet = false
                        Task { _ = await vm.setSource(familyId: familyId, place: place, url: text) }
                    }
                    .disabled(siteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Testi

    private static func confidenceSymbol(_ c: String) -> String {
        switch c {
        case "verified", "ai": return "checkmark.seal.fill"
        case "manual": return "person.fill.checkmark"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private static func confidenceText(_ c: String) -> LocalizedStringKey {
        switch c {
        case "verified": return "Fonte ufficiale"
        case "ai": return "Fonte ufficiale trovata dall'AI"
        case "manual": return "Sito scelto da te"
        default: return "Fonte da verificare"
        }
    }

    private static func dayLabel(_ key: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
