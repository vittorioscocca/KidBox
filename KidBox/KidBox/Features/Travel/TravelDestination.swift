//
//  TravelDestination.swift
//  KidBox
//

import Foundation

struct TravelDestination: Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    let tagline: String
    let whyForYou: String
    let aiHeadline: String
    let estimatedCost: String
    let durationDays: String
    let bestTime: String
    let bestTimeNote: String
    let isTopMatch: Bool
    private let previewPlanJson: String?

    /// Anteprima con `trip` o `dayPlans` utilizzabile senza rigenerare dal wizard.
    var hasStructuredAiPreview: Bool {
        TravelAIResponseParser.isStructuredTravelPlan(previewPlan)
    }

    /// Piano itinerario di anteprima (stesso schema di `generateTravelPlan`).
    var previewPlan: [String: Any]? {
        guard let previewPlanJson,
              let data = previewPlanJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
        self.region = dictionary["region"] as? String ?? ""
        self.tagline = dictionary["tagline"] as? String ?? ""
        self.whyForYou = dictionary["whyForYou"] as? String ?? ""
        self.aiHeadline = dictionary["aiHeadline"] as? String ?? ""
        self.estimatedCost = dictionary["estimatedCost"] as? String ?? ""
        self.durationDays = dictionary["durationDays"] as? String ?? ""
        self.bestTime = dictionary["bestTime"] as? String ?? ""
        self.bestTimeNote = dictionary["bestTimeNote"] as? String ?? ""
        self.isTopMatch = dictionary["isTopMatch"] as? Bool ?? false
        if let plan = dictionary["previewPlan"],
           JSONSerialization.isValidJSONObject(plan),
           let data = try? JSONSerialization.data(withJSONObject: plan),
           let json = String(data: data, encoding: .utf8) {
            self.previewPlanJson = json
        } else {
            self.previewPlanJson = nil
        }
    }

    var costDurationLine: String {
        "\(estimatedCost) per \(durationDays) giorni"
    }
}

struct TravelSuggestionsResponse {
    let destinations: [TravelDestination]
    let profileSummary: String
    let usageToday: Int
    let dailyLimit: Int
}

enum TravelDiscoverTips {
    /// `String` (non `LocalizedStringKey`): `title` è usato con `.uppercased()`,
    /// quindi passa da NSLocalizedString.
    static let items: [(title: String, body: String)] = [
        (NSLocalizedString("Lo sapevi?", comment: "Travel tip title"),
         NSLocalizedString("Il periodo migliore per Roma è aprile–maggio o settembre–ottobre. Meno folla, clima mite.", comment: "Travel tip body")),
        (NSLocalizedString("Lo sapevi?", comment: "Travel tip title"),
         NSLocalizedString("In primavera le città del Mediterraneo offrono sole e serate vivaci senza il caldo estivo.", comment: "Travel tip body")),
        (NSLocalizedString("Lo sapevi?", comment: "Travel tip title"),
         NSLocalizedString("Con bambini, 1–2 attività al giorno rendono il viaggio più piacevole per tutti.", comment: "Travel tip body")),
    ]

    static func random() -> (title: String, body: String) {
        items.randomElement() ?? items[0]
    }
}
