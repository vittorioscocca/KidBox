//
//  NewsView.swift
//  KidBox
//
//  La scheda Notizie (seconda radice della barra in basso). Tre stati prima del
//  contenuto: Free → invito a Pro; famiglia che non le ha mai accese →
//  presentazione con il costo in messaggi; accese da un qualunque membro →
//  l'edizione del giorno, dal paese alla città, con gli eventi vicini e, su
//  richiesta, le offerte su misura. Accensione, luogo, lingua e offerte sono
//  della famiglia (`NewsFamilyStore`): quello che trova uno lo leggono tutti.
//

import SwiftUI
import SwiftData
import SafariServices

struct NewsView: View {

    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var prefsStore = NewsPrefsStore.shared
    @ObservedObject private var familyStore = NewsFamilyStore.shared
    @StateObject private var vm = NewsViewModel()

    @State private var showSettings = false
    @State private var showUpgrade = false
    @State private var showOwnerOnly = false
    @State private var openedURL: NewsLink?
    /// Le offerte su misura mandano ad Anthropic dati della famiglia (bollette,
    /// spesa): passano dallo stesso consenso dell'assistente.
    @State private var showOffersConsent = false

    let familyId: String

    private var prefs: NewsPrefs { prefsStore.prefs }
    /// Le scelte della famiglia, solo quando sono di questa famiglia.
    private var family: NewsFamilySettings {
        familyStore.familyId == familyId ? familyStore.settings : NewsFamilySettings()
    }
    private var familyLoaded: Bool { familyStore.familyId == familyId && familyStore.isLoaded }

    /// Cambia quando cambia qualcosa che cambia l'edizione.
    private var loadKey: String {
        [familyId, prefs.categories.map(\.rawValue).joined(separator: ","), family.effectivePlace.label,
         family.effectiveLang, String(family.enabled)].joined(separator: "|")
    }

    var body: some View {
        Group {
            if subscriptionManager.currentPlan == .free {
                NewsLockedView {
                    if subscriptionManager.isFamilyOwner {
                        showUpgrade = true
                        AppAnalytics.aiPaywallShown(context: "news_tab")
                    } else {
                        showOwnerOnly = true
                    }
                }
            } else if !familyLoaded {
                // Le scelte della famiglia stanno arrivando: niente presentazione
                // a chi le ha già accese da un altro membro.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !family.enabled {
                NewsIntroView(place: family.effectivePlace, maxUnits: vm.feed?.maxUnitsPerEdition ?? 6) {
                    showSettings = true
                } onActivate: {
                    familyStore.update { $0.enabled = true }
                    AppAnalytics.newsActivated()
                }
            } else {
                content
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Notizie")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Text("Impostazioni delle notizie"))
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                NewsSettingsView(familyId: familyId)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fine") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(triggerFeature: "news")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .ownerOnlyAlert(isPresented: $showOwnerOnly)
        .sheet(item: $openedURL) { link in
            NewsSafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showOffersConsent) {
            AIConsentSheet {
                Task { await vm.searchOffers(familyId: familyId, family: family, context: modelContext) }
            }
        }
        .task { await prefsStore.refreshFromRemote() }
        .task(id: familyId) { familyStore.bind(familyId: familyId) }
        .task(id: loadKey) {
            guard subscriptionManager.currentPlan != .free, familyLoaded, family.enabled else { return }
            await vm.load(familyId: familyId, family: family, prefs: prefs, key: loadKey)
            await vm.loadSavedOffers(familyId: familyId, family: family, prefs: prefs)
        }
        .onDisappear { vm.stopPolling() }
    }

    // MARK: - Contenuto

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if let feed = vm.feed {
                    categoryChips
                    if feed.isPreparing { preparingBanner(pending: feed.pending) }
                    if !family.effectivePlace.hasCity { addCityCard }
                    if prefs.personalOffers, !vm.eventsOnly, vm.filter == nil || vm.filter == .economy { offersSection }
                    newsSections(feed)
                    eventsSection
                    if vm.visibleItems.isEmpty, vm.visibleEvents.isEmpty, !feed.isPreparing {
                        if vm.eventsOnly { noEventsState } else { emptyState }
                    }
                    disclaimer
                } else {
                    switch vm.phase {
                    case .failed(let error):
                        errorCard(error)
                    default:
                        preparingBanner(pending: ["country", "local"])
                        skeleton
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable {
            await vm.load(familyId: familyId, family: family, prefs: prefs, key: loadKey, force: true)
        }
    }

    // MARK: Intestazione

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(kbDeviceLocale())).capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                showSettings = true
            } label: {
                Label(family.effectivePlace.label, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.bubbleTint)
            }
            .buttonStyle(.plain)
            if let charge = vm.feed?.charge, charge.totalUnits > 0 {
                Text(String(format: NSLocalizedString("Edizione di oggi: %d messaggi AI", comment: "News: AI messages paid for today's edition"), charge.totalUnits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tutte", symbol: "square.grid.2x2", tint: KBTheme.bubbleTint, isOn: vm.filter == nil && !vm.eventsOnly) {
                    vm.filter = nil
                    vm.eventsOnly = false
                }
                chip(title: "Eventi", symbol: "calendar", tint: Self.eventsTint, isOn: vm.eventsOnly) {
                    vm.filter = nil
                    vm.eventsOnly.toggle()
                }
                ForEach(prefs.categories) { cat in
                    chip(title: cat.title, symbol: cat.symbol, tint: cat.tint, isOn: vm.filter == cat) {
                        vm.eventsOnly = false
                        vm.filter = vm.filter == cat ? nil : cat
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Colore della capsula «Eventi»: diverso da «Tempo libero», che gli
    /// eventi li comprende ma mostra anche le notizie.
    private static let eventsTint = Color(red: 0.557, green: 0.361, blue: 0.851)

    private func chip(title: LocalizedStringKey, symbol: String, tint: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.white : tint)
                .background(Capsule().fill(isOn ? tint : tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Stati

    private func preparingBanner(pending: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                if pending.contains("local") && !pending.contains("country") {
                    Text("Sto cercando le notizie della tua zona e gli eventi vicini…")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Sto cercando le notizie di oggi…")
                        .font(.subheadline.weight(.semibold))
                }
                Text("La prima edizione del giorno richiede circa un minuto. Puoi uscire: la ritrovi pronta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.cardBackground(colorScheme)))
    }

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .frame(height: 120)
                    .redacted(reason: .placeholder)
            }
        }
    }

    private func errorCard(_ error: NewsServiceError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(error.errorDescription ?? "")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.subheadline)
            Button("Riprova") {
                Task { await vm.load(familyId: familyId, family: family, prefs: prefs, key: loadKey, force: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(KBTheme.bubbleTint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.cardBackground(colorScheme)))
    }

    private var addCityCard: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(KBTheme.bubbleTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aggiungi la tua città")
                        .font(.subheadline.weight(.semibold))
                    Text("Per le notizie della tua regione e del tuo comune, e gli eventi entro 60 km.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.bubbleTint.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var noEventsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Oggi nessun evento vicino a te.")
                .font(.subheadline.weight(.semibold))
            Text("Gli eventi arrivano con l'edizione della tua città: cerco quelli entro una sessantina di chilometri.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Oggi niente di nuovo per gli argomenti che segui.")
                .font(.subheadline.weight(.semibold))
            Text("Quando non ci sono notizie utili l'edizione è più corta: meglio poche notizie vere che tante di riempimento.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var disclaimer: some View {
        Text("Notizie trovate e riassunte dall'AI dalle fonti indicate. Prima di fare domanda o di cambiare un contratto controlla sempre i dettagli sulla fonte.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    // MARK: Notizie

    @ViewBuilder
    private func newsSections(_ feed: NewsFeed) -> some View {
        let items = vm.visibleItems
        let groups = [
            NewsLevelGroup(id: "country", title: feed.place.country ?? "", symbol: "flag.fill"),
            NewsLevelGroup(id: "region", title: feed.place.region ?? "", symbol: "map.fill"),
            NewsLevelGroup(id: "city", title: feed.place.city ?? "", symbol: "building.2.fill"),
        ]
        ForEach(groups) { group in
            let levelItems = items.filter { $0.level == group.id }
            if !levelItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(group.title.isEmpty ? NSLocalizedString("Notizie", comment: "News: section fallback title") : group.title,
                                 symbol: group.symbol)
                    ForEach(levelItems) { item in
                        NewsItemCard(item: item) {
                            open(item.url)
                            AppAnalytics.newsItemOpened(kind: "news", category: item.category, level: item.level)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .padding(.top, 4)
    }

    // MARK: Eventi

    @ViewBuilder
    private var eventsSection: some View {
        let events = vm.visibleEvents
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Eventi vicino a te", systemImage: "ticket.fill")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(events) { event in
                    NewsEventCard(event: event) {
                        open(event.url)
                        AppAnalytics.newsItemOpened(kind: "event", category: "leisure", level: "city")
                    }
                }
            }
        }
    }

    // MARK: Offerte su misura

    private var offersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Su misura per voi", systemImage: "sparkles")
                .font(.headline)
                .padding(.top, 4)
            if let offers = vm.offers?.offers, !offers.isEmpty {
                ForEach(offers) { offer in
                    NewsOfferCard(offer: offer) {
                        open(offer.url)
                        AppAnalytics.newsItemOpened(kind: "offer", category: offer.kind, level: "personal")
                    }
                }
                if let ms = vm.offers?.generatedAt {
                    Text(String(format: NSLocalizedString("Offerte cercate %@", comment: "News: when personal offers were searched"),
                                Date(timeIntervalSince1970: ms / 1000).formatted(.relative(presentation: .named).locale(kbDeviceLocale()))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if vm.offers?.status == "fresh" {
                Text("Per oggi nessuna offerta più conveniente di quello che avete già.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            offersButton
            if let message = vm.offersError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var offersButton: some View {
        Button {
            guard AISettings.shared.consentGiven else {
                showOffersConsent = true
                return
            }
            Task { await vm.searchOffers(familyId: familyId, family: family, context: modelContext) }
        } label: {
            HStack(spacing: 10) {
                if vm.isSearchingOffers {
                    ProgressView().tint(.white)
                    Text("Sto confrontando bollette e offerte…")
                } else {
                    Image(systemName: "magnifyingglass")
                    if vm.offers?.offers.isEmpty == false {
                        Text("Cerca di nuovo")
                    } else {
                        Text("Cerca offerte da bollette e spesa")
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.bubbleTint))
        }
        .buttonStyle(.plain)
        .disabled(vm.isSearchingOffers)
        .overlay(alignment: .bottom) {
            if !vm.isSearchingOffers {
                Text(String(format: NSLocalizedString("Circa %d messaggi AI · usa le bollette in Casa e la lista della spesa", comment: "News: cost of personal offers"),
                            vm.offers?.estimateUnits ?? 8))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 18)
            }
        }
        .padding(.bottom, 16)
    }

    private func open(_ raw: String) {
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return }
        openedURL = NewsLink(url: url)
    }
}

// MARK: - Presentazione e invito

/// Prima attivazione: cosa fa, quanto costa in messaggi, dove.
private struct NewsIntroView: View {
    let place: NewsPlace
    let maxUnits: Int
    let onEditPlace: () -> Void
    let onActivate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(KBTheme.bubbleTint)
                    .padding(.top, 12)
                Text("Le notizie che servono alla tua famiglia")
                    .font(.title2.bold())
                VStack(alignment: .leading, spacing: 14) {
                    bullet("gift.fill", "Ogni giorno fino a 10 notizie su bonus, scuola, salute ed economia, dal tuo paese alla tua città.")
                    bullet("ticket.fill", "Eventi per famiglie entro 60 km.")
                    bullet("sparkles", "Offerte su misura da bollette e lista della spesa, quando le chiedi.")
                    bullet("link", "Ogni notizia con la sua fonte, e niente riempitivi: se non c'è niente di nuovo, l'edizione è più corta.")
                }
                Button(action: onEditPlace) {
                    HStack {
                        Label(place.label, systemImage: "mappin.and.ellipse")
                        Spacer()
                        Text("Cambia").foregroundStyle(KBTheme.bubbleTint)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.10)))
                }
                .buttonStyle(.plain)
                Text(String(format: NSLocalizedString("Le ricerche si pagano in messaggi AI: ogni edizione al massimo %d messaggi, e meno quando la leggono anche altre famiglie della tua zona.", comment: "News intro: cost in AI messages"), maxUnits))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: onActivate) {
                    Text("Attiva le notizie")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.bubbleTint))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(KBTheme.bubbleTint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

/// Piano Free: cosa c'è dentro, e il passaggio a Pro.
private struct NewsLockedView: View {
    let onUpgrade: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(KBTheme.bubbleTint)
                    .padding(.top, 24)
                Text("Notizie per la tua famiglia")
                    .font(.title2.bold())
                Text("Bonus, scuola, salute, economia ed eventi vicino a te, cercati ogni giorno dall'AI con la loro fonte. Incluse nei piani Pro e Max.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(NewsCategory.allCases) { cat in
                        Label(cat.title, systemImage: cat.symbol)
                            .foregroundStyle(cat.tint)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 4)
                Button(action: onUpgrade) {
                    Text("Scopri Pro")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.bubbleTint))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Browser in app

struct NewsLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct NewsSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
