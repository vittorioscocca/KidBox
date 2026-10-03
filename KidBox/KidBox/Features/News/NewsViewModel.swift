//
//  NewsViewModel.swift
//  KidBox
//
//  Carica l'edizione del giorno e la richiede finché il server la sta ancora
//  preparando: le edizioni si generano in coda (40-100 s), non dentro la
//  chiamata, quindi la prima apertura della giornata mostra quello che c'è e
//  si completa da sola.
//

import Foundation
import Combine
import SwiftData
import FirebaseAuth

@MainActor
final class NewsViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(NewsServiceError)
    }

    @Published private(set) var feed: NewsFeed?
    @Published private(set) var phase: Phase = .idle
    @Published var filter: NewsCategory?
    /// Capsula «Eventi»: solo gli eventi vicini, niente notizie né offerte.
    /// Esclude `filter`: toccare un argomento la spegne, e viceversa.
    @Published var eventsOnly = false

    @Published private(set) var offers: NewsOffersPayload?
    @Published private(set) var isSearchingOffers = false
    @Published private(set) var offersError: String?

    private var pollTask: Task<Void, Never>?
    private var loadedKey: String?

    /// Dopo così tante richieste senza edizione pronta (~4 minuti) si smette:
    /// il prossimo «aggiorna» riparte.
    private let maxPolls = 40
    private let pollInterval: Duration = .seconds(6)

    // MARK: - Edizione

    /// `key` cambia quando cambiano famiglia, categorie, luogo o lingua.
    func load(familyId: String, family: NewsFamilySettings, prefs: NewsPrefs, key: String, force: Bool = false) async {
        guard !familyId.isEmpty, family.enabled else { return }
        if !force, loadedKey == key, feed != nil { return }
        if !force, feed == nil, let cached = NewsService.shared.cachedFeed,
           cached.familyId == familyId, cached.dateKey == NewsDates.key(Date()) {
            feed = cached.feed
            phase = .ready
        }
        pollTask?.cancel()
        if feed == nil { phase = .loading }
        do {
            let fresh = try await NewsService.shared.fetchFeed(familyId: familyId, family: family, prefs: prefs)
            apply(fresh, key: key)
            if fresh.isPreparing { startPolling(familyId: familyId, family: family, prefs: prefs, key: key) }
            AppAnalytics.newsOpened(items: fresh.items.count, events: fresh.events.count, units: fresh.charge.units, preparing: fresh.isPreparing)
        } catch let error as NewsServiceError {
            phase = .failed(error)
        } catch {
            phase = .failed(.network(error.localizedDescription))
        }
    }

    private func apply(_ fresh: NewsFeed, key: String) {
        feed = fresh
        loadedKey = key
        phase = .ready
        if let saved = fresh.offers { offers = saved }
    }

    private func startPolling(familyId: String, family: NewsFamilySettings, prefs: NewsPrefs, key: String) {
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<maxPolls {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled { return }
                guard let fresh = try? await NewsService.shared.fetchFeed(familyId: familyId, family: family, prefs: prefs) else { continue }
                if Task.isCancelled { return }
                self.apply(fresh, key: key)
                if !fresh.isPreparing { return }
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    /// Le notizie con il filtro della riga di categorie.
    var visibleItems: [NewsItem] {
        guard let items = feed?.items, !eventsOnly else { return [] }
        guard let filter else { return items }
        return items.filter { $0.category == filter.rawValue }
    }

    var visibleEvents: [NewsEvent] {
        guard let events = feed?.events else { return [] }
        if eventsOnly { return events }
        if let filter, filter != .leisure { return [] }
        return events
    }

    // MARK: - Offerte su misura

    func loadSavedOffers(familyId: String, family: NewsFamilySettings, prefs: NewsPrefs) async {
        guard family.enabled, prefs.personalOffers, offers == nil else { return }
        offers = try? await NewsService.shared.fetchOffers(familyId: familyId, family: family, brief: nil)
    }

    func searchOffers(familyId: String, family: NewsFamilySettings, context: ModelContext) async {
        let brief = NewsBriefBuilder.build(familyId: familyId, uid: Auth.auth().currentUser?.uid, context: context)
        guard !brief.isEmpty else {
            offersError = NewsServiceError.emptyBrief.errorDescription
            return
        }
        isSearchingOffers = true
        offersError = nil
        defer { isSearchingOffers = false }
        do {
            offers = try await NewsService.shared.fetchOffers(familyId: familyId, family: family, brief: brief)
            AppAnalytics.newsOffersSearched(offers: offers?.offers.count ?? 0, units: offers?.units ?? 0)
        } catch let error as NewsServiceError {
            offersError = error.errorDescription
        } catch {
            offersError = error.localizedDescription
        }
    }
}
