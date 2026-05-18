//
//  TravelDiscoverViewModel.swift
//  KidBox
//

import Foundation
import Combine

@MainActor
final class TravelDiscoverViewModel: ObservableObject {

    @Published var destinations: [TravelDestination] = []
    @Published var profileSummary: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    let familyId: String
    private let userId: String
    private let aiService = AIService.shared

    init(familyId: String, userId: String) {
        self.familyId = familyId
        self.userId = userId
    }

    var subtitle: String {
        if !profileSummary.isEmpty { return profileSummary }
        return TravelProfileStore.loadProfile(userId: userId)?.discoverSubtitle ?? ""
    }

    func loadSuggestions(force: Bool = false) async {
        if isLoading { return }
        if !force, !destinations.isEmpty { return }

        isLoading = true
        errorMessage = nil

        guard let profile = TravelProfileStore.loadProfile(userId: userId) else {
            errorMessage = "Completa prima le preferenze di viaggio."
            isLoading = false
            return
        }

        do {
            let response = try await aiService.suggestTravelDestinations(
                TravelSuggestionsRequest(travelProfile: profile.familyContextValue()),
                familyId: familyId
            )
            destinations = response.destinations
            TravelSuggestionCache.store(destinations, familyId: familyId)
            profileSummary = response.profileSummary
        } catch let error as AIServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
