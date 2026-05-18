//
//  TravelDayRegeneration.swift
//  KidBox
//

import Foundation

/// Normalizza mappe/array annidati restituiti da Firebase Callable (NSDictionary / NSArray).
enum TravelJSONCoercion {

    static func dictionary(_ value: Any?) -> [String: Any]? {
        switch value {
        case let dict as [String: Any]:
            return deepDictionary(dict)
        case let dict as NSDictionary:
            var swift: [String: Any] = [:]
            dict.forEach { key, val in
                if let k = key as? String { swift[k] = val }
            }
            return deepDictionary(swift)
        case let json as String:
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return dictionary(obj)
        default:
            return nil
        }
    }

    static func arrayOfDictionaries(_ value: Any?) -> [[String: Any]] {
        switch value {
        case let array as [[String: Any]]:
            return array.map(deepDictionary)
        case let array as [Any]:
            return array.compactMap { dictionary($0) }
        case let array as NSArray:
            return array.compactMap { dictionary($0) }
        default:
            return []
        }
    }

    static func travelPlan(_ value: Any?) -> [String: Any]? {
        dictionary(value)
    }

    static func dayPlans(from plan: [String: Any]) -> [[String: Any]] {
        arrayOfDictionaries(plan["dayPlans"])
    }

    private static func deepDictionary(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(dict.count)
        for (key, value) in dict {
            switch value {
            case let nested as [String: Any]:
                result[key] = deepDictionary(nested)
            case let nested as NSDictionary:
                var swift: [String: Any] = [:]
                nested.forEach { k, v in
                    if let k = k as? String { swift[k] = v }
                }
                result[key] = deepDictionary(swift)
            case let array as [[String: Any]]:
                result[key] = array.map(deepDictionary)
            case let array as [Any] where array.first is [String: Any] || array.first is NSDictionary:
                result[key] = arrayOfDictionaries(array)
            case let array as NSArray:
                result[key] = arrayOfDictionaries(array)
            default:
                result[key] = value
            }
        }
        return result
    }
}

enum TravelDayRegeneration {

    static func legsPayload(
        from wizardLegs: [TravelPlanningViewModel.LegDraft],
        tripLegs: [KBTripLeg],
        fallbackLocation: String
    ) -> [[String: Any]] {
        if !wizardLegs.isEmpty {
            return wizardLegs.enumerated().map { index, leg in
                [
                    "order": index + 1,
                    "fromLocation": leg.fromLocation,
                    "toLocation": leg.toLocation,
                    "transportMode": leg.transportMode.rawValue,
                    "days": leg.days,
                ] as [String: Any]
            }
        }
        if !tripLegs.isEmpty {
            return tripLegs.sorted { $0.order < $1.order }.map { leg in
                [
                    "order": leg.order,
                    "fromLocation": leg.fromLocation,
                    "toLocation": leg.toLocation,
                    "transportMode": leg.transportModeRaw,
                    "days": 1,
                ] as [String: Any]
            }
        }
        let place = fallbackLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = place.isEmpty ? "Destinazione" : place
        return [[
            "order": 1,
            "fromLocation": label,
            "toLocation": label,
            "transportMode": TransportMode.car.rawValue,
            "days": 1,
        ] as [String: Any]]
    }

    static func wizardData(
        tripName: String,
        day: TravelItineraryDay,
        budgetPerDay: Double,
        currency: String,
        legs: [[String: Any]]
    ) -> [String: Any] {
        [
            "tripName": tripName,
            "startDate": day.dateString,
            "endDate": day.dateString,
            "budgetTotal": budgetPerDay,
            "currency": currency,
            "legs": legs,
        ]
    }

    static func regenerationPrompt(day: TravelItineraryDay, otherPlaces: String) -> String {
        "Rigenera SOLO il giorno \(day.dayIndex) (data: \(day.dateString), location: \(day.location)). " +
            "NON riproporre questi luoghi già inclusi negli altri giorni: \(otherPlaces.isEmpty ? "nessuno" : otherPlaces). " +
            "La risposta JSON deve contenere ESATTAMENTE 1 elemento in dayPlans con la stessa data \(day.dateString), " +
            "con morningStops, afternoonStops e eveningStops (minimo 2 tappe per fascia quando possibile) e nomi reali dei locali."
    }

    static func collectOtherDaysPlaces(from proposal: [String: Any]?, excludingDate: String) -> String {
        guard let proposal else { return "" }
        let days = TravelJSONCoercion.dayPlans(from: proposal)
        guard !days.isEmpty else { return "" }
        var places: [String] = []
        for day in days {
            guard (day["date"] as? String) != excludingDate else { continue }
            for period in ["morningStops", "afternoonStops", "eveningStops"] {
                let stops = TravelJSONCoercion.arrayOfDictionaries(day[period])
                for stop in stops {
                    if let name = stop["title"] as? String, !name.isEmpty {
                        places.append(name)
                    } else if let name = stop["name"] as? String, !name.isEmpty {
                        places.append(name)
                    }
                }
            }
        }
        return Array(Set(places)).prefix(25).joined(separator: ", ")
    }

    static func collectOtherDaysPlaces(from proposalJson: String?, excludingDate: String) -> String {
        guard let proposalJson,
              let data = proposalJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        return collectOtherDaysPlaces(from: root, excludingDate: excludingDate)
    }

    static func extractRegeneratedDay(
        from response: TravelPlanResponse,
        dateString: String
    ) -> [String: Any]? {
        if let plan = response.travelPlan {
            if let day = dayMatching(plan: plan, dateString: dateString) {
                return TravelJSONCoercion.dictionary(day) ?? day
            }
        }
        let narrative = response.narrativeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !narrative.isEmpty,
           let parsed = TravelAIResponseParser.parseTravelPlan(from: narrative),
           let day = dayMatching(plan: parsed, dateString: dateString) {
            return TravelJSONCoercion.dictionary(day) ?? day
        }
        return nil
    }

    static func mergeDay(into proposal: [String: Any], newDay: [String: Any], dateString: String) -> [String: Any] {
        var merged = TravelJSONCoercion.dictionary(proposal) ?? proposal
        var days = TravelJSONCoercion.dayPlans(from: merged)
        var normalized = TravelJSONCoercion.dictionary(newDay) ?? newDay
        if (normalized["date"] as? String)?.isEmpty != false {
            normalized["date"] = dateString
        }
        if let idx = days.firstIndex(where: { ($0["date"] as? String) == dateString }) {
            days[idx] = normalized
        } else {
            days.append(normalized)
        }
        merged["dayPlans"] = days
        return merged
    }

    static func mergeDay(into proposalJson: String?, newDay: [String: Any], dateString: String) -> String? {
        var root: [String: Any]
        if let proposalJson,
           let data = proposalJson.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        } else {
            root = [:]
        }
        let merged = mergeDay(into: root, newDay: newDay, dateString: dateString)
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let json = String(data: data, encoding: .utf8) else {
            return proposalJson
        }
        return json
    }

    static func applyDayToModel(
        _ dayPlan: KBTripDayPlan,
        from newDay: [String: Any],
        fallbackLocation: String
    ) {
        let location = (newDay["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let location, !location.isEmpty {
            dayPlan.location = location
        }
        dayPlan.morningPlan = newDay["morningPlan"] as? String ?? dayPlan.morningPlan
        dayPlan.afternoonPlan = newDay["afternoonPlan"] as? String ?? dayPlan.afternoonPlan
        dayPlan.eveningPlan = newDay["eveningPlan"] as? String ?? dayPlan.eveningPlan
        dayPlan.accommodationName = newDay["accommodationName"] as? String
        dayPlan.accommodationType = newDay["accommodationType"] as? String
        dayPlan.accommodationCostPerNight = newDay["accommodationCostPerNight"] as? Double
        dayPlan.weatherBackupPlan = newDay["weatherBackupPlan"] as? String
        dayPlan.estimatedDailyCost = newDay["estimatedDailyCost"] as? Double
        if dayPlan.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dayPlan.location = fallbackLocation
        }
        dayPlan.updatedAt = Date()
    }

    private static func dayMatching(plan: [String: Any], dateString: String) -> [String: Any]? {
        let days = TravelJSONCoercion.dayPlans(from: plan)
        guard !days.isEmpty else { return nil }
        if let match = days.first(where: { ($0["date"] as? String) == dateString }) {
            return match
        }
        return days.first
    }
}
