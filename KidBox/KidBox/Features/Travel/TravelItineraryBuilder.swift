//
//  TravelItineraryBuilder.swift
//  KidBox
//

import Foundation

enum TravelItineraryBuilder {

    static func build(
        trip: KBTrip,
        dayPlans: [KBTripDayPlan],
        legs: [KBTripLeg],
        members: [KBFamilyMember],
        children: [KBChild],
        proposalOverride: [String: Any]? = nil
    ) -> TravelItineraryOverview {
        let proposal = proposalOverride ?? parseProposalJson(trip.aiProposalJson)
        let tripMeta = proposal?["trip"] as? [String: Any]
        let estimated = (tripMeta?["estimatedTotalCost"] as? NSNumber)?.doubleValue
            ?? dayPlans.compactMap(\.estimatedDailyCost).reduce(0, +)
        let currency = (tripMeta?["currency"] as? String) ?? trip.currency
        let breakdown = budgetBreakdown(
            from: tripMeta?["budgetBreakdown"] as? [String: Any],
            estimatedTotal: estimated > 0 ? estimated : trip.budgetTotal,
            dayPlans: dayPlans,
            legs: legs
        )

        let destination = destinationTitle(from: trip.name)
        let travelerLine = travelerSummary(
            participantIdsJson: trip.participantIdsJson,
            members: members,
            children: children
        )
        let dayCount = trip.plannedDayCount
        let subtitle = "Italia · \(dayCount) \(dayCount == 1 ? "giorno" : "giorni") · \(travelerLine)"

        let alignedPlans = alignedDayPlans(for: trip, dayPlans: dayPlans, proposal: proposal)
        let proposalDays = proposal.map { TravelJSONCoercion.dayPlans(from: $0) }
        let days: [TravelItineraryDay] = alignedPlans.enumerated().map { index, plan in
            let proposalDay = proposalDays?.first { ($0["date"] as? String) == plan.dateString }
                ?? proposalDays?[safe: index]
            return buildDay(
                plan: plan,
                dayIndex: index + 1,
                proposalDay: proposalDay
            )
        }

        return TravelItineraryOverview(
            destinationTitle: destination,
            subtitle: subtitle,
            dayCount: dayCount,
            estimatedTotal: estimated > 0 ? estimated : trip.budgetTotal,
            budgetLimit: trip.budgetTotal,
            currency: currency,
            budget: breakdown,
            days: days
        )
    }

    /// Allinea i `dayPlans` salvati al numero di giorni del viaggio (uno per data consecutiva).
    static func normalizeDayPlansForTrip(
        _ trip: KBTrip,
        parsedPlans: [KBTripDayPlan],
        proposal: [String: Any]?
    ) -> [KBTripDayPlan] {
        alignedDayPlans(for: trip, dayPlans: parsedPlans, proposal: proposal)
    }

    private static func alignedDayPlans(
        for trip: KBTrip,
        dayPlans: [KBTripDayPlan],
        proposal: [String: Any]?
    ) -> [KBTripDayPlan] {
        let plannedCount = trip.plannedDayCount
        let dateStrings = Date.kbTripDateStrings(from: trip.startDate, dayCount: plannedCount)
        let proposalDays = proposal.map { TravelJSONCoercion.dayPlans(from: $0) }
        let destination = destinationTitle(from: trip.name)

        return dateStrings.enumerated().map { index, dateString in
            if let existing = dayPlans.first(where: { $0.dateString == dateString }) {
                return existing
            }
            if let proposalDay = proposalDays?.first(where: { ($0["date"] as? String) == dateString })
                ?? proposalDays?[safe: index] {
                return dayPlan(from: proposalDay, trip: trip, dateString: dateString, location: destination)
            }
            return syntheticDayPlan(
                trip: trip,
                dateString: dateString,
                dayIndex: index + 1,
                location: destination
            )
        }
    }

    private static func dayPlan(
        from dict: [String: Any],
        trip: KBTrip,
        dateString: String,
        location: String
    ) -> KBTripDayPlan {
        let plan = KBTripDayPlan(
            familyId: trip.familyId,
            tripId: trip.id,
            dateString: dateString,
            location: {
                let value = (dict["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? location : value
            }(),
            morningPlan: dict["morningPlan"] as? String ?? "",
            afternoonPlan: dict["afternoonPlan"] as? String ?? "",
            eveningPlan: dict["eveningPlan"] as? String ?? ""
        )
        plan.accommodationName = dict["accommodationName"] as? String
        plan.accommodationType = dict["accommodationType"] as? String
        plan.accommodationCostPerNight = dict["accommodationCostPerNight"] as? Double
        plan.weatherBackupPlan = dict["weatherBackupPlan"] as? String
        plan.estimatedDailyCost = dict["estimatedDailyCost"] as? Double
        return plan
    }

    private static func syntheticDayPlan(
        trip: KBTrip,
        dateString: String,
        dayIndex: Int,
        location: String
    ) -> KBTripDayPlan {
        KBTripDayPlan(
            familyId: trip.familyId,
            tripId: trip.id,
            dateString: dateString,
            location: location,
            morningPlan: dayIndex == 1
                ? "Mattina di arrivo e primo giro in \(location)"
                : "Mattina libera a \(location)",
            afternoonPlan: "Pomeriggio per scoprire \(location)",
            eveningPlan: "Sera a \(location)"
        )
    }

    /// Costruisce la vista itinerario dalla risposta AI del wizard (prima del salvataggio su disco).
    static func buildFromProposal(
        _ proposal: [String: Any],
        tripName: String,
        budgetLimit: Double,
        currency: String,
        participantIdsJson: String,
        members: [KBFamilyMember],
        children: [KBChild],
        plannedDayCount: Int
    ) -> TravelItineraryOverview {
        let tripMeta = proposal["trip"] as? [String: Any]
        let estimated = (tripMeta?["estimatedTotalCost"] as? NSNumber)?.doubleValue ?? budgetLimit
        let resolvedCurrency = (tripMeta?["currency"] as? String) ?? currency
        let breakdown = budgetBreakdown(
            from: tripMeta?["budgetBreakdown"] as? [String: Any],
            estimatedTotal: estimated > 0 ? estimated : budgetLimit,
            dayPlans: [],
            legs: []
        )

        let destination = destinationTitle(from: tripName)
        let proposalDays = TravelJSONCoercion.dayPlans(from: proposal)
        let dayCount = max(proposalDays.count, plannedDayCount, 1)
        let dayWord = dayCount == 1 ? "giorno" : "giorni"
        let travelers = travelerSummary(
            participantIdsJson: participantIdsJson,
            members: members,
            children: children
        )
        let subtitle = "Italia · \(dayCount) \(dayWord) · \(travelers)"

        let days = proposalDays.enumerated().map { index, proposalDay in
            buildDayFromProposal(dayIndex: index + 1, proposalDay: proposalDay)
        }

        return TravelItineraryOverview(
            destinationTitle: destination,
            subtitle: subtitle,
            dayCount: dayCount,
            estimatedTotal: estimated > 0 ? estimated : budgetLimit,
            budgetLimit: budgetLimit,
            currency: resolvedCurrency,
            budget: breakdown,
            days: days
        )
    }

    /// Anteprima itinerario per un suggerimento «Scopri» (preview AI o piano sintetico).
    static func buildFromSuggestion(_ destination: TravelDestination) -> TravelItineraryOverview {
        let budget = parseEstimatedCost(destination.estimatedCost) ?? 1_200
        let dayCount = max(parseDurationDays(destination.durationDays), 1)

        let proposal: [String: Any]
        if let preview = destination.previewPlan, !preview.isEmpty {
            proposal = preview
        } else {
            proposal = syntheticPreviewPlan(for: destination, dayCount: min(dayCount, 4), budget: budget)
        }

        let base = buildFromProposal(
            proposal,
            tripName: "Viaggio a \(destination.name)",
            budgetLimit: budget,
            currency: "EUR",
            participantIdsJson: "[]",
            members: [],
            children: [],
            plannedDayCount: dayCount
        )

        let regionLine = destination.region.isEmpty ? destination.name : destination.region
        let days = base.dayCount
        return TravelItineraryOverview(
            destinationTitle: destination.name,
            subtitle: "\(regionLine) · \(days) \(days == 1 ? "giorno" : "giorni") · Anteprima AI",
            dayCount: base.dayCount,
            estimatedTotal: base.estimatedTotal,
            budgetLimit: base.budgetLimit,
            currency: base.currency,
            budget: base.budget,
            days: base.days
        )
    }

    static func parseEstimatedCost(_ text: String) -> Double? {
        let pattern = #"(\d+(?:[.,]\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    static func parseDurationDays(_ text: String) -> Int {
        let numbers = text
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .filter { $0 > 0 }
        guard !numbers.isEmpty else { return 3 }
        return numbers.max() ?? numbers[0]
    }

    private static func syntheticPreviewPlan(
        for destination: TravelDestination,
        dayCount: Int,
        budget: Double
    ) -> [String: Any] {
        let hotels = budget * 0.36
        let flights = budget * 0.22
        let restaurants = budget * 0.22
        let activities = max(budget - hotels - flights - restaurants, budget * 0.12)
        let location = destination.region.isEmpty ? destination.name : destination.name

        let dayPlans: [[String: Any]] = (1...dayCount).map { index in
            let isFirst = index == 1
            let isLast = index == dayCount
            return [
                "date": "2026-06-\(String(format: "%02d", index))",
                "location": location,
                "estimatedDailyCost": budget / Double(dayCount),
                "morningStops": [
                    stop(
                        time: "09:30",
                        title: isFirst ? "Arrivo e check-in a \(destination.name)" : "Colazione e passeggiata",
                        minutes: 90,
                        cost: isFirst ? "~\(Int(budget * 0.08))" : "Gratis",
                        category: isFirst ? "hotel" : "culture"
                    ),
                ],
                "afternoonStops": [
                    stop(
                        time: "13:00",
                        title: "Osteria \(destination.name) — pranzo tipico",
                        minutes: 75,
                        cost: "~\(Int(budget * 0.04))",
                        category: "food"
                    ),
                    stop(
                        time: "14:30",
                        title: destination.tagline.isEmpty ? "Esplora il centro storico" : destination.tagline,
                        minutes: 120,
                        cost: "~\(Int(budget * 0.06))",
                        category: "culture"
                    ),
                ],
                "eveningStops": [
                    stop(
                        time: "19:30",
                        title: isLast
                            ? "Ristorante \(destination.name) — cena di arrivederci"
                            : "Trattoria del Porto — cucina di pesce",
                        minutes: 90,
                        cost: "~\(Int(budget * 0.05))",
                        category: "food"
                    ),
                ],
            ] as [String: Any]
        }

        return [
            "trip": [
                "estimatedTotalCost": budget,
                "currency": "EUR",
                "summary": destination.aiHeadline.isEmpty ? destination.tagline : destination.aiHeadline,
                "budgetBreakdown": [
                    "hotels": hotels,
                    "flights": flights,
                    "restaurants": restaurants,
                    "activities": activities,
                ],
            ] as [String: Any],
            "dayPlans": dayPlans,
        ]
    }

    private static func stop(
        time: String,
        title: String,
        minutes: Int,
        cost: String,
        category: String
    ) -> [String: Any] {
        [
            "time": time,
            "title": title,
            "durationMinutes": minutes,
            "costLabel": cost,
            "category": category,
        ]
    }

    static func destinationTitle(from tripName: String) -> String {
        let prefix = "Viaggio a "
        if tripName.hasPrefix(prefix) {
            return String(tripName.dropFirst(prefix.count))
        }
        return tripName
    }

    static func travelerSummary(
        participantIdsJson: String,
        members: [KBFamilyMember],
        children: [KBChild]
    ) -> String {
        guard let data = participantIdsJson.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data),
              !ids.isEmpty else {
            return "Famiglia"
        }
        let lines: [String] = ids.compactMap { id in
            if let child = children.first(where: { $0.id == id }) {
                let age = child.ageDescription
                return age.isEmpty ? child.name : "\(child.name) (\(age))"
            }
            if let member = members.first(where: { $0.userId == id }) {
                return member.displayName ?? "Adulto"
            }
            return nil
        }
        return lines.isEmpty ? "Famiglia" : lines.joined(separator: ", ")
    }

    private static func parseProposalJson(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return TravelJSONCoercion.dictionary(obj)
    }

    private static func buildDayFromProposal(dayIndex: Int, proposalDay: [String: Any]) -> TravelItineraryDay {
        let location = proposalDay["location"] as? String ?? ""
        let dateString = proposalDay["date"] as? String ?? ""
        let blocks: [TravelItineraryPeriodBlock] = [
            buildBlock(
                period: .morning,
                text: proposalDay["morningPlan"] as? String ?? "",
                structured: TravelJSONCoercion.arrayOfDictionaries(proposalDay["morningStops"])
            ),
            buildBlock(
                period: .afternoon,
                text: proposalDay["afternoonPlan"] as? String ?? "",
                structured: TravelJSONCoercion.arrayOfDictionaries(proposalDay["afternoonStops"])
            ),
            buildBlock(
                period: .evening,
                text: proposalDay["eveningPlan"] as? String ?? "",
                structured: TravelJSONCoercion.arrayOfDictionaries(proposalDay["eveningStops"])
            ),
        ].filter { !$0.stops.isEmpty }

        let headline = location.isEmpty
            ? "Giorno \(dayIndex)"
            : (dayIndex == 1 ? "Arrivo a \(location)" : location)

        return TravelItineraryDay(
            id: "\(dayIndex)-\(dateString)",
            dayIndex: dayIndex,
            dateString: dateString,
            location: location,
            headline: headline,
            dayCost: (proposalDay["estimatedDailyCost"] as? NSNumber)?.doubleValue,
            blocks: blocks
        )
    }

    private static func buildDay(
        plan: KBTripDayPlan,
        dayIndex: Int,
        proposalDay: [String: Any]?
    ) -> TravelItineraryDay {
        let blocks: [TravelItineraryPeriodBlock] = [
            buildBlock(
                period: .morning,
                text: plan.morningPlan,
                structured: TravelJSONCoercion.arrayOfDictionaries(proposalDay?["morningStops"])
            ),
            buildBlock(
                period: .afternoon,
                text: plan.afternoonPlan,
                structured: TravelJSONCoercion.arrayOfDictionaries(proposalDay?["afternoonStops"])
            ),
            buildBlock(
                period: .evening,
                text: plan.eveningPlan,
                structured: TravelJSONCoercion.arrayOfDictionaries(proposalDay?["eveningStops"])
            ),
        ].filter { !$0.stops.isEmpty }

        let headline = plan.location.isEmpty
            ? "Giorno \(dayIndex)"
            : (dayIndex == 1 ? "Arrivo a \(plan.location)" : plan.location)

        return TravelItineraryDay(
            id: plan.id,
            dayIndex: dayIndex,
            dateString: plan.dateString,
            location: plan.location,
            headline: headline,
            dayCost: plan.estimatedDailyCost,
            blocks: blocks
        )
    }

    private static func buildBlock(
        period: TravelItineraryPeriod,
        text: String,
        structured: [[String: Any]]?
    ) -> TravelItineraryPeriodBlock {
        let stops: [TravelItineraryStop]
        if let structured, !structured.isEmpty {
            stops = structured.compactMap { parseStructuredStop($0) }
        } else {
            stops = parseTextStops(text)
        }
        return TravelItineraryPeriodBlock(
            period: period,
            stops: stops,
            durationSummary: summarizeDuration(stops),
            costSummary: summarizeCost(stops)
        )
    }

    private static func parseStructuredStop(_ dict: [String: Any]) -> TravelItineraryStop? {
        let title = resolveStopTitle(from: dict)
        guard !title.isEmpty else { return nil }
        let time = (dict["time"] as? String)
            ?? (dict["startTime"] as? String)
            ?? (dict["hour"] as? String)
            ?? ""
        let duration = (dict["durationMinutes"] as? NSNumber)?.intValue
            ?? (dict["duration"] as? NSNumber)?.intValue
        let costLabel = (dict["costLabel"] as? String) ?? (dict["price"] as? String)
        let cost = (dict["cost"] as? NSNumber)?.doubleValue
            ?? (dict["estimatedCost"] as? NSNumber)?.doubleValue
        let category = TravelItineraryStopCategory.from(raw: dict["category"] as? String)
        let detail = formatDetail(durationMinutes: duration, cost: cost, costLabel: costLabel)
        return TravelItineraryStop(
            time: time,
            title: title,
            detail: detail,
            emoji: category.emoji,
            category: category
        )
    }

    private static func resolveStopTitle(from dict: [String: Any]) -> String {
        let candidates = ["title", "name", "place", "location", "label", "activity", "description"]
        for key in candidates {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    private static func parseTextStops(_ text: String) -> [TravelItineraryStop] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = trimmed
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { $0.components(separatedBy: " · ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count <= 1 {
            let category = categoryForTitle(trimmed)
            return [TravelItineraryStop(time: "", title: trimmed, detail: "", emoji: category.emoji, category: category)]
        }

        return lines.compactMap { parseTextLine($0) }
    }

    private static func parseTextLine(_ line: String) -> TravelItineraryStop? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let timePattern = #"^(\d{1,2}:\d{2})\s*[-–—]?\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let timeRange = Range(match.range(at: 1), in: trimmed),
           let restRange = Range(match.range(at: 2), in: trimmed) {
            let time = String(trimmed[timeRange])
            let rest = String(trimmed[restRange])
            let (title, detail) = splitTitleDetail(rest)
            let category = categoryForTitle(title)
            return TravelItineraryStop(
                time: time,
                title: title,
                detail: detail,
                emoji: category.emoji,
                category: category
            )
        }

        let category = categoryForTitle(trimmed)
        return TravelItineraryStop(time: "", title: trimmed, detail: "", emoji: category.emoji, category: category)
    }

    private static func splitTitleDetail(_ rest: String) -> (String, String) {
        if let open = rest.lastIndex(of: "("), let close = rest.lastIndex(of: ")"), open < close {
            let title = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = rest[rest.index(after: open)..<close]
                .replacingOccurrences(of: "•", with: "·")
            return (String(title), String(detail))
        }
        if let sep = rest.range(of: " · ") {
            return (String(rest[..<sep.lowerBound]), String(rest[sep.upperBound...]))
        }
        return (rest, "")
    }

    private static func formatDetail(durationMinutes: Int?, cost: Double?, costLabel: String?) -> String {
        var parts: [String] = []
        if let durationMinutes, durationMinutes > 0 {
            if durationMinutes < 60 {
                parts.append("\(durationMinutes)m")
            } else {
                let h = durationMinutes / 60
                let m = durationMinutes % 60
                parts.append(m == 0 ? "\(h)h" : "\(h)h \(m)m")
            }
        }
        if let costLabel, !costLabel.isEmpty {
            parts.append(costLabel)
        } else if let cost {
            parts.append(cost <= 0 ? "Gratis" : String(format: "~%.0f", cost))
        }
        return parts.joined(separator: " · ")
    }

    private static func summarizeDuration(_ stops: [TravelItineraryStop]) -> String {
        let minutes = stops.compactMap { stop -> Int? in
            let pattern = #"(\d+)\s*m"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: stop.detail, range: NSRange(stop.detail.startIndex..., in: stop.detail)),
                  let range = Range(match.range(at: 1), in: stop.detail) else { return nil }
            return Int(stop.detail[range])
        }.reduce(0, +)
        guard minutes > 0 else { return "" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func summarizeCost(_ stops: [TravelItineraryStop]) -> String {
        let values = stops.compactMap { stop -> Double? in
            let pattern = #"~?(\d+(?:[.,]\d+)?)"#
            guard stop.detail.localizedCaseInsensitiveContains("gratis") == false,
                  let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: stop.detail, range: NSRange(stop.detail.startIndex..., in: stop.detail)),
                  let range = Range(match.range(at: 1), in: stop.detail) else { return nil }
            return Double(stop.detail[range].replacingOccurrences(of: ",", with: "."))
        }
        guard !values.isEmpty else { return "" }
        let sum = values.reduce(0, +)
        return sum > 0 ? String(format: "~%.0f", sum) : ""
    }

    private static func categoryForTitle(_ title: String) -> TravelItineraryStopCategory {
        let lower = title.lowercased()
        if lower.contains("aeroport") || lower.contains("volo") || lower.contains("flight") { return .flight }
        if lower.contains("taxi") || lower.contains("bus") || lower.contains("traghetto") || lower.contains("metro") { return .transport }
        if containsAny(lower, foodNeedles) { return .food }
        if lower.contains("hotel") || lower.contains("suite") || lower.contains("bb") { return .hotel }
        if lower.contains("muse") || lower.contains("castell") || lower.contains("chiesa") { return .culture }
        if lower.contains("spiagg") || lower.contains("marina") { return .beach }
        return .other
    }

    private static func emojiForTitle(_ title: String) -> String {
        categoryForTitle(title).emoji
    }

    private static func budgetBreakdown(
        from dict: [String: Any]?,
        estimatedTotal: Double,
        dayPlans: [KBTripDayPlan],
        legs: [KBTripLeg]
    ) -> TravelItineraryBudgetBreakdown {
        if let dict {
            return TravelItineraryBudgetBreakdown(
                hotels: (dict["hotels"] as? NSNumber)?.doubleValue ?? 0,
                flights: (dict["flights"] as? NSNumber)?.doubleValue ?? 0,
                restaurants: (dict["restaurants"] as? NSNumber)?.doubleValue ?? 0,
                activities: (dict["activities"] as? NSNumber)?.doubleValue ?? 0
            )
        }

        let hotelNights = dayPlans.compactMap(\.accommodationCostPerNight).reduce(0, +)
        let hotels = hotelNights > 0 ? hotelNights * Double(max(dayPlans.count - 1, 1)) : estimatedTotal * 0.35
        let hasFlight = legs.contains { $0.transportModeRaw == "flight" }
        let flights = hasFlight ? estimatedTotal * 0.28 : estimatedTotal * 0.1
        let restaurants = estimatedTotal * 0.18
        let activities = max(estimatedTotal - hotels - flights - restaurants, estimatedTotal * 0.12)
        return TravelItineraryBudgetBreakdown(
            hotels: hotels,
            flights: flights,
            restaurants: restaurants,
            activities: activities
        )
    }

    static func collectHotels(
        dayPlans: [KBTripDayPlan],
        overview: TravelItineraryOverview
    ) -> [TravelPlaceResult] {
        var results: [TravelPlaceResult] = []
        var seen = Set<String>()

        for plan in dayPlans {
            let name = plan.accommodationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }

            var parts: [String] = []
            if let type = plan.accommodationType, !type.isEmpty { parts.append(typeLabel(type)) }
            if let cost = plan.accommodationCostPerNight, cost > 0 {
                parts.append(String(format: "~%.0f €/notte", cost))
            }
            if !plan.location.isEmpty { parts.append(plan.location) }

            let locationContext = Self.placeSearchLocationContext(
                dayLocation: plan.location,
                destinationTitle: overview.destinationTitle
            )
            results.append(
                TravelPlaceResult(
                    title: name,
                    subtitle: parts.joined(separator: " · "),
                    meta: formattedDayLabel(plan.dateString),
                    placeName: name,
                    locationContext: locationContext
                )
            )
        }

        appendStops(from: overview, matching: isHotelStop, into: &results, seen: &seen)
        return results
    }

    static func collectRestaurants(
        dayPlans: [KBTripDayPlan],
        overview: TravelItineraryOverview,
        proposalJson: String? = nil
    ) -> [TravelPlaceResult] {
        var results: [TravelPlaceResult] = []
        var seen = Set<String>()

        if let proposal = parseProposalJson(proposalJson) {
            appendDiningPlaces(
                from: proposal,
                destinationTitle: overview.destinationTitle,
                into: &results,
                seen: &seen
            )
            appendFoodStopsFromProposal(
                proposal,
                destinationTitle: overview.destinationTitle,
                into: &results,
                seen: &seen
            )
        }

        for day in overview.days {
            for block in day.blocks {
                for stop in block.stops where isRestaurantStop(stop) {
                    let locationContext = Self.placeSearchLocationContext(
                        dayLocation: day.location,
                        destinationTitle: overview.destinationTitle
                    )
                    let displayName = displayRestaurantName(
                        title: stop.title,
                        detail: stop.detail,
                        location: day.location
                    )
                    appendRestaurant(
                        name: displayName,
                        subtitle: restaurantSubtitle(detail: stop.detail, location: day.location, cuisine: nil),
                        meta: restaurantMeta(dateString: day.dateString, time: stop.time, meal: nil),
                        locationContext: locationContext,
                        placeName: placeQueryName(title: stop.title, subtitle: stop.detail),
                        into: &results,
                        seen: &seen
                    )
                }
            }
        }

        for plan in dayPlans {
            let location = plan.location
            let locationContext = Self.placeSearchLocationContext(
                dayLocation: location,
                destinationTitle: overview.destinationTitle
            )
            let dayMeta = formattedDayLabel(plan.dateString)
            for text in [plan.morningPlan, plan.afternoonPlan, plan.eveningPlan] {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                for stop in parseTextStops(trimmed) where isRestaurantStop(stop) {
                    appendRestaurant(
                        name: displayRestaurantName(title: stop.title, detail: stop.detail, location: location),
                        subtitle: restaurantSubtitle(detail: stop.detail, location: location, cuisine: nil),
                        meta: restaurantMeta(dateString: plan.dateString, time: stop.time, meal: nil),
                        locationContext: locationContext,
                        placeName: placeQueryName(title: stop.title, subtitle: stop.detail),
                        into: &results,
                        seen: &seen
                    )
                }

                for name in extractVenueNames(from: trimmed) {
                    appendRestaurant(
                        name: name,
                        subtitle: location,
                        meta: dayMeta,
                        locationContext: locationContext,
                        placeName: name,
                        into: &results,
                        seen: &seen
                    )
                }
            }
        }

        return results.sorted { $0.meta.localizedCompare($1.meta) == .orderedAscending }
    }

    static func collectActivities(
        dayPlans: [KBTripDayPlan],
        overview: TravelItineraryOverview,
        proposalJson: String? = nil
    ) -> [TravelPlaceResult] {
        var results: [TravelPlaceResult] = []
        var seen = Set<String>()

        if let proposal = parseProposalJson(proposalJson) {
            appendActivityStopsFromProposal(
                proposal,
                destinationTitle: overview.destinationTitle,
                into: &results,
                seen: &seen
            )
        }

        appendStops(from: overview, matching: isActivityStop, into: &results, seen: &seen)

        for plan in dayPlans {
            let location = plan.location
            let locationContext = Self.placeSearchLocationContext(
                dayLocation: location,
                destinationTitle: overview.destinationTitle
            )
            for text in [plan.morningPlan, plan.afternoonPlan, plan.eveningPlan] {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                for stop in parseTextStops(trimmed) where isActivityStop(stop) {
                    appendActivity(
                        name: stop.title,
                        subtitle: activitySubtitle(detail: stop.detail, location: location),
                        meta: activityMeta(dateString: plan.dateString, time: stop.time),
                        locationContext: locationContext,
                        placeName: placeQueryName(title: stop.title, subtitle: stop.detail),
                        into: &results,
                        seen: &seen
                    )
                }
            }
        }

        return results.sorted { $0.meta.localizedCompare($1.meta) == .orderedAscending }
    }

    private static func appendStops(
        from overview: TravelItineraryOverview,
        matching predicate: (TravelItineraryStop) -> Bool,
        into results: inout [TravelPlaceResult],
        seen: inout Set<String>
    ) {
        for day in overview.days {
            for block in day.blocks {
                for stop in block.stops where predicate(stop) {
                    let key = stop.title.lowercased()
                    guard seen.insert(key).inserted else { continue }
                    var meta = formattedDayLabel(day.dateString)
                    if !stop.time.isEmpty {
                        meta = meta.isEmpty ? stop.time : "\(meta) · \(stop.time)"
                    }
                    results.append(
                        TravelPlaceResult(
                            title: stop.title,
                            subtitle: stop.detail,
                            meta: meta,
                            placeName: placeQueryName(title: stop.title, subtitle: stop.detail),
                            locationContext: Self.placeSearchLocationContext(
                                dayLocation: day.location,
                                destinationTitle: overview.destinationTitle
                            )
                        )
                    )
                }
            }
        }
    }

    private static func isHotelStop(_ stop: TravelItineraryStop) -> Bool {
        stop.emoji == "🏨" || containsAny(stop.title.lowercased(), ["hotel", "bb", "suite", "alloggio", "resort"])
    }

    private static let foodNeedles = [
        "ristor", "trattoria", "osteria", "pizzeria", "enoteca", "taverna", "locanda",
        "bistrot", "bacaro", "friggitoria", "gastronomia", "street food", "mercato",
        "degustazione", "cucina", "pranzo", "cena", "colazione", "aperitivo", "brunch",
        "gelateria", "pasticceria", "panificio", "pescheria", "food",
    ]

    private static let genericMealTitles = [
        "cena", "pranzo", "colazione", "aperitivo", "spuntino", "merenda", "brunch",
        "cena tipica", "cena tipica locale", "cena di arrivederci", "pranzo veloce",
        "pranzo leggero", "colazione e passeggiata", "cibo di strada",
    ]

    private static func isRestaurantStop(_ stop: TravelItineraryStop) -> Bool {
        if stop.category == .food { return true }
        let blob = "\(stop.title) \(stop.detail)".lowercased()
        return stop.emoji == "🍝" || containsAny(blob, foodNeedles)
    }

    private static let activityExclusionNeedles = [
        "tempo libero", "giornata libera", "riposo", "trasferimento",
        "check-in", "check-out", "volo", "aeroporto", "imbarco", "sbarco",
        "taxi", "bus", "treno", "navetta", "traghetto",
    ]

    private static func isActivityStop(_ stop: TravelItineraryStop) -> Bool {
        if isHotelStop(stop) || isRestaurantStop(stop) { return false }
        switch stop.category {
        case .flight, .transport, .hotel, .food:
            return false
        case .culture, .beach, .shopping:
            return !isGenericActivityTitle(stop.title)
        case .other:
            let blob = "\(stop.title) \(stop.detail)".lowercased()
            if containsAny(blob, activityExclusionNeedles) { return false }
            return stop.title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                && !isGenericMealTitle(stop.title)
        }
    }

    private static func isGenericActivityTitle(_ title: String) -> Bool {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return containsAny(normalized, activityExclusionNeedles)
    }

    private static func appendDiningPlaces(
        from proposal: [String: Any],
        destinationTitle: String,
        into results: inout [TravelPlaceResult],
        seen: inout Set<String>
    ) {
        guard let places = proposal["diningPlaces"] as? [[String: Any]] else { return }
        for place in places {
            let rawName = (place["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawName.isEmpty else { continue }
            let location = (place["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cuisine = (place["cuisine"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let meal = (place["meal"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (place["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let day = (place["day"] as? String) ?? ""
            var detailParts: [String] = []
            if let cuisine, !cuisine.isEmpty { detailParts.append(cuisine) }
            if !notes.isEmpty { detailParts.append(notes) }
            if let cost = place["estimatedCost"] as? NSNumber, cost.doubleValue > 0 {
                detailParts.append(String(format: "~%.0f €", cost.doubleValue))
            }
            let locationContext = placeSearchLocationContext(
                dayLocation: location,
                destinationTitle: destinationTitle
            )
            appendRestaurant(
                name: rawName,
                subtitle: restaurantSubtitle(detail: detailParts.joined(separator: " · "), location: location, cuisine: nil),
                meta: restaurantMeta(dateString: day, time: "", meal: meal),
                locationContext: locationContext,
                placeName: rawName,
                into: &results,
                seen: &seen
            )
        }
    }

    private static func appendActivityStopsFromProposal(
        _ proposal: [String: Any],
        destinationTitle: String,
        into results: inout [TravelPlaceResult],
        seen: inout Set<String>
    ) {
        guard let dayPlans = proposal["dayPlans"] as? [[String: Any]] else { return }
        for day in dayPlans {
            let location = (day["location"] as? String) ?? ""
            let locationContext = placeSearchLocationContext(
                dayLocation: location,
                destinationTitle: destinationTitle
            )
            let dateString = (day["date"] as? String) ?? ""
            for key in ["morningStops", "afternoonStops", "eveningStops"] {
                guard let stops = day[key] as? [[String: Any]] else { continue }
                for stopDict in stops {
                    guard let stop = parseStructuredStop(stopDict) else { continue }
                    guard isActivityStop(stop) else { continue }
                    appendActivity(
                        name: stop.title,
                        subtitle: activitySubtitle(detail: stop.detail, location: location),
                        meta: activityMeta(dateString: dateString, time: stop.time),
                        locationContext: locationContext,
                        placeName: placeQueryName(title: stop.title, subtitle: stop.detail),
                        into: &results,
                        seen: &seen
                    )
                }
            }
        }
    }

    private static func appendFoodStopsFromProposal(
        _ proposal: [String: Any],
        destinationTitle: String,
        into results: inout [TravelPlaceResult],
        seen: inout Set<String>
    ) {
        guard let dayPlans = proposal["dayPlans"] as? [[String: Any]] else { return }
        for day in dayPlans {
            let location = (day["location"] as? String) ?? ""
            let locationContext = placeSearchLocationContext(
                dayLocation: location,
                destinationTitle: destinationTitle
            )
            let dateString = (day["date"] as? String) ?? ""
            for key in ["morningStops", "afternoonStops", "eveningStops"] {
                guard let stops = day[key] as? [[String: Any]] else { continue }
                for stopDict in stops {
                    let category = TravelItineraryStopCategory.from(raw: stopDict["category"] as? String)
                    guard category == .food else { continue }
                    let title = (stopDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !title.isEmpty else { continue }
                    let time = stopDict["time"] as? String ?? ""
                    let detail = formatDetail(
                        durationMinutes: (stopDict["durationMinutes"] as? NSNumber)?.intValue,
                        cost: (stopDict["cost"] as? NSNumber)?.doubleValue,
                        costLabel: stopDict["costLabel"] as? String
                    )
                    appendRestaurant(
                        name: displayRestaurantName(title: title, detail: detail, location: location),
                        subtitle: restaurantSubtitle(detail: detail, location: location, cuisine: nil),
                        meta: restaurantMeta(dateString: dateString, time: time, meal: mealLabel(for: key)),
                        locationContext: locationContext,
                        placeName: placeQueryName(title: title, subtitle: detail),
                        into: &results,
                        seen: &seen
                    )
                }
            }
        }
    }

    private static func appendActivity(
        name: String,
        subtitle: String,
        meta: String,
        locationContext: String,
        placeName: String? = nil,
        into results: inout [TravelPlaceResult],
        seen: inout Set<String>
    ) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isGenericMealTitle(cleaned), !isGenericActivityTitle(cleaned) else { return }
        let key = cleaned.lowercased()
        guard seen.insert(key).inserted else { return }
        let queryName = placeName ?? placeQueryName(title: cleaned, subtitle: subtitle)
        results.append(
            TravelPlaceResult(
                title: cleaned,
                subtitle: subtitle,
                meta: meta,
                placeName: queryName,
                locationContext: locationContext
            )
        )
    }

    private static func activitySubtitle(detail: String, location: String) -> String {
        var parts: [String] = []
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDetail.isEmpty { parts.append(trimmedDetail) }
        if !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private static func activityMeta(dateString: String, time: String) -> String {
        var parts: [String] = []
        let dayLabel = formattedDayLabel(dateString)
        if !dayLabel.isEmpty, dayLabel != dateString { parts.append(dayLabel) }
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    private static func appendRestaurant(
        name: String,
        subtitle: String,
        meta: String,
        locationContext: String,
        placeName: String? = nil,
        into results: inout [TravelPlaceResult],
        seen: inout Set<String>
    ) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isGenericMealTitle(cleaned) else { return }
        let key = cleaned.lowercased()
        guard seen.insert(key).inserted else { return }
        let queryName = placeName ?? placeQueryName(title: cleaned, subtitle: subtitle)
        results.append(
            TravelPlaceResult(
                title: cleaned,
                subtitle: subtitle,
                meta: meta,
                placeName: queryName,
                locationContext: locationContext
            )
        )
    }

    /// Nome luogo per Google Places (estrae il locale da titoli lunghi).
    static func placeQueryName(title: String, subtitle: String = "") -> String {
        let cleaned = cleanVenueTitle(title)
        if !isGenericMealTitle(cleaned), cleaned.count <= 72 { return cleaned }
        if let extracted = extractVenueNames(from: "\(title) \(subtitle)").first {
            return extracted
        }
        return cleaned
    }

    /// Contesto geografico per Google Places.
    static func placeSearchLocationContext(dayLocation: String, destinationTitle: String) -> String {
        let day = dayLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = destinationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if day.isEmpty { return dest }
        if dest.isEmpty { return day }
        if day.localizedCaseInsensitiveCompare(dest) == .orderedSame { return day }
        if day.localizedCaseInsensitiveContains(dest) { return day }
        return "\(day), \(dest)"
    }

    private static func displayRestaurantName(title: String, detail: String, location: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isGenericMealTitle(trimmed) {
            return cleanVenueTitle(trimmed)
        }
        if let extracted = extractVenueNames(from: "\(title) \(detail)").first {
            return extracted
        }
        if !location.isEmpty {
            return "Locale consigliato · \(location)"
        }
        return trimmed
    }

    private static func cleanVenueTitle(_ title: String) -> String {
        if let dash = title.range(of: " — ") ?? title.range(of: " - ") {
            let left = String(title[..<dash.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !isGenericMealTitle(left) { return left }
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func restaurantSubtitle(detail: String, location: String, cuisine: String?) -> String {
        var parts: [String] = []
        if let cuisine, !cuisine.isEmpty { parts.append(cuisine) }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDetail.isEmpty { parts.append(trimmedDetail) }
        if !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private static func restaurantMeta(dateString: String, time: String, meal: String?) -> String {
        var parts: [String] = []
        let day = formattedDayLabel(dateString)
        if !day.isEmpty, day != dateString { parts.append(day) }
        if let meal, !meal.isEmpty { parts.append(meal.capitalized) }
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    private static func mealLabel(for stopsKey: String) -> String? {
        switch stopsKey {
        case "morningStops": return "Colazione"
        case "afternoonStops": return "Pranzo"
        case "eveningStops": return "Cena"
        default: return nil
        }
    }

    private static func isGenericMealTitle(_ title: String) -> Bool {
        let normalized = title
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if genericMealTitles.contains(normalized) { return true }
        return normalized.count < 12 && containsAny(normalized, ["cena", "pranzo", "colazione", "aperitivo"])
    }

    private static func extractVenueNames(from text: String) -> [String] {
        var names: [String] = []
        let patterns = [
            #"(?i)(ristorante|trattoria|osteria|pizzeria|enoteca|taverna|locanda|bistrot|bacaro|friggitoria)\s+([^·(,.\n]+)"#,
            #"(?i)\b(da|al|alla|dal|dalla)\s+([A-ZÀ-Ÿ][\w\s'’]+)"#,
            #"«([^»]+)»"#,
            #""([^"]+)""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                let index = match.numberOfRanges >= 3 ? 2 : 1
                guard match.numberOfRanges > index,
                      let nameRange = Range(match.range(at: index), in: text) else { return }
                let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 3, !isGenericMealTitle(name) {
                    names.append(cleanVenueTitle(name))
                }
            }
        }
        return names
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func lineTitle(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.firstIndex(of: "(") {
            return String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let sep = trimmed.range(of: " · ") {
            return String(trimmed[..<sep.lowerBound])
        }
        return trimmed
    }

    private static func typeLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "hotel": return "Hotel"
        case "bb": return "B&B"
        case "camping": return "Campeggio"
        case "airbnb": return "Appartamento"
        default: return raw.capitalized
        }
    }

    private static func formattedDayLabel(_ iso: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: iso) else { return iso }
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
