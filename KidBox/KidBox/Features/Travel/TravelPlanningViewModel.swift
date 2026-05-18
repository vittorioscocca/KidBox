//
//  TravelPlanningViewModel.swift
//  KidBox
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class TravelPlanningViewModel: ObservableObject {

    @Published var destinationName = ""
    @Published var destinationRegion = ""
    @Published var tripName = ""
    @Published var startDate = Date()
    @Published var endDate = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
    @Published var primaryTransport: WizardPrimaryTransport = .car
    @Published var selectedParticipantIds: Set<String> = []
    @Published var legs: [LegDraft] = []
    @Published var budgetTotal: Double = 4_000
    @Published var currency = "EUR"
    @Published var usesCustomBudget = false
    @Published var customBudgetInput = ""
    @Published var tripStyles: Set<TravelStyle> = []
    @Published var freeTextPrompt = ""

    @Published var proposalNarrative: String?
    @Published var proposalPlan: [String: Any]?
    @Published var isGenerating = false
    @Published var generationError: String?
    @Published var usageToday: Int = 0
    @Published var dailyLimit: Int = 0

    @Published var acceptedTrip: KBTrip?
    @Published var regeneratingDayIndex: Int?
    /// Incrementato ad ogni merge del piano: forza il refresh della UI proposta.
    @Published private(set) var proposalRevision = 0

    struct LegDraft: Identifiable {
        var id = UUID()
        var fromLocation = ""
        var toLocation = ""
        var transportMode: TransportMode = .car
        var days: Int = 1
    }

    private let modelContext: ModelContext
    private let coordinator: AppCoordinator
    private let aiService = AIService.shared
    private let tripRemote = TripRemoteStore()

    init(modelContext: ModelContext, coordinator: AppCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
    }

    static let totalWizardSteps = 7

    var activeFamilyId: String { coordinator.activeFamilyId ?? "" }

    var tripDayCount: Int {
        endDate.kbDayCount(from: startDate)
    }

    var canGenerate: Bool {
        !destinationName.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedParticipantIds.isEmpty
            && !tripStyles.isEmpty
            && budgetTotal > 0
    }

    func canProceed(step: Int, members: [KBFamilyMember], children: [KBChild]) -> Bool {
        switch step {
        case 0: return destinationName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case 1: return endDate >= startDate
        case 2: return true
        case 3: return !selectedParticipantIds.isEmpty
        case 4: return budgetTotal > 0
        case 5: return !tripStyles.isEmpty
        default: return canGenerate
        }
    }

    func applyPrefill(destination: String, region: String = "") {
        destinationName = destination
        destinationRegion = region
        syncTripFromWizardInputs()
    }

    func loadTripStylesFromProfile(userId: String) {
        guard let profile = TravelProfileStore.loadProfile(userId: userId) else { return }
        tripStyles = Set(profile.styles)
    }

    func selectAllParticipants(members: [KBFamilyMember], children: [KBChild]) {
        selectedParticipantIds = Set(members.map(\.userId) + children.map(\.id))
    }

    func syncTripFromWizardInputs() {
        let place = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty {
            tripName = "Viaggio a \(place)"
        }
        let days = max(tripDayCount, 1)
        if legs.isEmpty {
            legs = [
                LegDraft(
                    fromLocation: "",
                    toLocation: place,
                    transportMode: primaryTransport.transportMode,
                    days: days
                ),
            ]
        } else {
            updateLeg(at: 0) { leg in
                leg.toLocation = place
                leg.transportMode = primaryTransport.transportMode
                leg.days = days
            }
        }
    }

    func applyBudgetPreset(_ preset: TravelWizardBudgetPreset) {
        usesCustomBudget = false
        budgetTotal = preset.amount(in: currency)
        customBudgetInput = String(Int(budgetTotal))
    }

    func enableCustomBudget() {
        usesCustomBudget = true
        if customBudgetInput.isEmpty {
            customBudgetInput = String(max(Int(budgetTotal), 0))
        }
    }

    func updateCustomBudget(from text: String) {
        let digits = text.filter { $0.isNumber }
        customBudgetInput = digits
        if digits.isEmpty {
            budgetTotal = 0
            return
        }
        if let value = Double(digits) {
            budgetTotal = value > 0 ? value : 0
        }
    }

    func matchesBudgetPreset(_ preset: TravelWizardBudgetPreset) -> Bool {
        guard !usesCustomBudget else { return false }
        return Int(budgetTotal.rounded()) == Int(preset.amount(in: currency).rounded())
    }

    func participantLines(members: [KBFamilyMember], children: [KBChild]) -> [TravelWizardParticipantLine] {
        let adultLines = members.map { member in
            TravelWizardParticipantLine(
                id: member.userId,
                name: member.displayName ?? "Membro",
                ageLabel: "Adulto",
                emoji: "🧑",
                isChild: false
            )
        }
        let childLines = children.map { child in
            TravelWizardParticipantLine(
                id: child.id,
                name: child.name,
                ageLabel: child.ageDescription.isEmpty ? "Bambino" : child.ageDescription,
                emoji: child.avatarEmoji,
                isChild: true
            )
        }
        return adultLines + childLines
    }

    func selectedParticipantSummary(members: [KBFamilyMember], children: [KBChild]) -> String {
        let lines = participantLines(members: members, children: children)
            .filter { selectedParticipantIds.contains($0.id) }
        if lines.isEmpty { return "Nessun viaggiatore selezionato" }
        return lines.map { line in
            if line.ageLabel == "Adulto" || line.ageLabel.isEmpty {
                return line.name
            }
            return "\(line.name) (\(line.ageLabel))"
        }.joined(separator: ", ")
    }

    func budgetFootnote(members: [KBFamilyMember], children: [KBChild]) -> String {
        let count = selectedParticipantIds.count
        let names = selectedParticipantSummary(members: members, children: children)
        let perDay = budgetTotal / Double(max(tripDayCount, 1))
        let symbol = currency == "EUR" ? "€" : "$"
        return "per \(tripDayCount) giorni · \(count) \(count == 1 ? "persona" : "persone") · \(names) · ~\(Int(perDay)) \(symbol)/giorno"
    }

    var composedFreeTextPrompt: String {
        var parts: [String] = []
        if !freeTextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(freeTextPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !tripStyles.isEmpty {
            let styles = tripStyles.map(\.title).sorted().joined(separator: ", ")
            parts.append("Stili per questo viaggio: \(styles).")
        }
        if !destinationRegion.isEmpty {
            parts.append("Destinazione: \(destinationName), \(destinationRegion).")
        }
        return parts.joined(separator: "\n")
    }

    func addLeg() {
        legs = legs + [LegDraft()]
    }

    func removeLeg(at offsets: IndexSet) {
        var updated = legs
        updated.remove(atOffsets: offsets)
        legs = updated
    }

    func updateLeg(at index: Int, _ update: (inout LegDraft) -> Void) {
        guard legs.indices.contains(index) else { return }
        var updated = legs
        update(&updated[index])
        legs = updated
    }

    func selectAllParticipants(childIds: [String], memberUserIds: [String]) {
        selectedParticipantIds = Set(childIds + memberUserIds)
    }

    func deselectAllParticipants() {
        selectedParticipantIds = []
    }

    func setParticipantSelected(_ id: String, selected: Bool) {
        var updated = selectedParticipantIds
        if selected {
            updated.insert(id)
        } else {
            updated.remove(id)
        }
        selectedParticipantIds = updated
    }

    func generatePlan(
        children: [KBChild],
        pediatricProfiles: [KBPediatricProfile],
        members: [KBFamilyMember]
    ) async {
        guard canGenerate else { return }
        await KBSubscriptionManager.shared.loadPlan()
        guard KBSubscriptionManager.shared.currentPlan.includesAI else {
            generationError = "Piano Pro o Max richiesto. Controlla l'abbonamento Apple o il campo planOverride (pro/max) su Firebase per questa famiglia."
            return
        }
        guard AISettings.shared.isEnabled else {
            generationError = AIServiceError.notEnabled.localizedDescription
            return
        }

        if let usage = try? await aiService.fetchUsage() {
            usageToday = usage.usageToday
            dailyLimit = usage.dailyLimit
        }

        let messageCost = TravelPlanningCountdown.messageCost(plannedDayCount: tripDayCount)
        if dailyLimit > 0, usageToday + messageCost > dailyLimit {
            generationError = "Questo viaggio di \(tripDayCount) giorni richiede \(messageCost) messaggi AI (\(usageToday)/\(dailyLimit) usati oggi). Accorcia il viaggio o riprova domani."
            return
        }

        isGenerating = true
        generationError = nil
        proposalNarrative = nil
        proposalPlan = nil

        let familyId = coordinator.activeFamilyId ?? ""
        guard !familyId.isEmpty else {
            generationError = AIServiceError.missingFamilyId.localizedDescription
            isGenerating = false
            return
        }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        let wizardData: [String: Any] = [
            "tripName": tripName,
            "startDate": fmt.string(from: startDate),
            "endDate": fmt.string(from: endDate),
            "budgetTotal": budgetTotal,
            "currency": currency,
            "legs": legs.enumerated().map { index, leg in
                [
                    "order": index + 1,
                    "fromLocation": leg.fromLocation,
                    "toLocation": leg.toLocation,
                    "transportMode": leg.transportMode.rawValue,
                    "days": leg.days,
                ] as [String: Any]
            },
        ]

        let selectedChildren = children.filter { selectedParticipantIds.contains($0.id) }
        let childrenContext: [[String: Any]] = selectedChildren.compactMap { child in
            guard let birthDate = child.birthDate else { return nil }
            let profile = pediatricProfiles.first { $0.childId == child.id }
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
            var dict: [String: Any] = [
                "name": child.name,
                "birthDate": fmt.string(from: birthDate),
                "age": age,
            ]
            if let allergies = profile?.allergies, !allergies.isEmpty { dict["allergies"] = allergies }
            if let notes = profile?.medicalNotes, !notes.isEmpty { dict["medicalNotes"] = notes }
            return dict
        }

        let participantNames = members
            .filter { selectedParticipantIds.contains($0.userId) }
            .compactMap(\.displayName)

        var familyContext: [String: Any] = [
            "children": childrenContext,
            "participants": participantNames,
            "participantSummary": selectedParticipantSummary(members: members, children: children),
        ]
        if let uid = coordinator.uid,
           let profile = TravelProfileStore.loadProfile(userId: uid) {
            familyContext["travelProfile"] = profile.familyContextValue()
        }
        if !tripStyles.isEmpty {
            familyContext["tripStyles"] = tripStyles.map(\.rawValue)
        }

        do {
            let response = try await aiService.generateTravelPlan(
                TravelPlanRequest(
                    wizardData: wizardData,
                    freeTextPrompt: composedFreeTextPrompt,
                    familyContext: familyContext
                ),
                familyId: familyId
            )
            let rawText = response.narrativeText
            proposalNarrative = TravelAIResponseParser.sanitizedNarrative(from: rawText)
            proposalPlan = TravelAIResponseParser.isStructuredTravelPlan(response.travelPlan)
                ? response.travelPlan
                : TravelAIResponseParser.parseTravelPlan(from: rawText)
            usageToday = response.usageToday
            dailyLimit = response.dailyLimit
            AIUsageStore.shared.apply(usageToday: response.usageToday, dailyLimit: response.dailyLimit)
        } catch let error as AIServiceError {
            generationError = error.errorDescription
        } catch {
            generationError = error.localizedDescription
        }
        isGenerating = false
    }

    func regenerate(
        children: [KBChild],
        pediatricProfiles: [KBPediatricProfile],
        members: [KBFamilyMember]
    ) async {
        await generatePlan(children: children, pediatricProfiles: pediatricProfiles, members: members)
    }

    /// Accetta l'anteprima «Scopri» come viaggio pianificato (senza rigenerare dal wizard).
    @discardableResult
    func acceptPreviewFromSuggestion(
        destination: TravelDestination,
        familyId: String,
        members: [KBFamilyMember],
        children: [KBChild]
    ) -> String? {
        guard let plan = destination.previewPlan,
              TravelAIResponseParser.isStructuredTravelPlan(plan) else {
            generationError = "Itinerario non disponibile."
            return nil
        }
        applySuggestionPrefill(from: destination, plan: plan)
        if selectedParticipantIds.isEmpty {
            selectAllParticipants(members: members, children: children)
        }
        return acceptProposal(familyId: familyId)
    }

    private func applySuggestionPrefill(from destination: TravelDestination, plan: [String: Any]) {
        destinationName = destination.name
        destinationRegion = destination.region
        tripName = "Viaggio a \(destination.name)"

        if let tripMeta = plan["trip"] as? [String: Any] {
            if let cost = tripMeta["estimatedTotalCost"] as? Double {
                budgetTotal = cost
            } else if let cost = tripMeta["estimatedTotalCost"] as? Int {
                budgetTotal = Double(cost)
            }
            if let curr = tripMeta["currency"] as? String, !curr.isEmpty {
                currency = curr
            }
            if let summary = tripMeta["summary"] as? String, !summary.isEmpty {
                proposalNarrative = summary
            }
        }
        if budgetTotal <= 0 {
            budgetTotal = TravelItineraryBuilder.parseEstimatedCost(destination.estimatedCost) ?? 4_000
        }
        if proposalNarrative == nil, !destination.aiHeadline.isEmpty {
            proposalNarrative = destination.aiHeadline
        }

        let dayPlans = plan["dayPlans"] as? [[String: Any]] ?? []
        let dayCount = max(
            dayPlans.isEmpty ? TravelItineraryBuilder.parseDurationDays(destination.durationDays) : dayPlans.count,
            1
        )

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        if let firstDateStr = dayPlans.first?["date"] as? String,
           let first = fmt.date(from: firstDateStr) {
            startDate = first
            endDate = Calendar.current.date(byAdding: .day, value: dayCount - 1, to: startDate) ?? startDate
        } else {
            let cal = Calendar.current
            startDate = cal.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            endDate = cal.date(byAdding: .day, value: dayCount - 1, to: startDate) ?? startDate
        }

        proposalPlan = plan
        syncTripFromWizardInputs()
    }

    /// Salva il viaggio in SwiftData. Restituisce l'id del trip o nil se fallisce.
    @discardableResult
    func acceptProposal(familyId explicitFamilyId: String? = nil) -> String? {
        guard let plan = proposalPlan,
              let familyId = explicitFamilyId ?? coordinator.activeFamilyId,
              let uid = coordinator.uid else { return nil }

        let trip = KBTrip(
            familyId: familyId,
            name: tripName,
            startDate: startDate,
            endDate: endDate,
            budgetTotal: budgetTotal,
            currency: currency,
            createdBy: uid
        )

        if let data = try? JSONSerialization.data(withJSONObject: Array(selectedParticipantIds)),
           let json = String(data: data, encoding: .utf8) {
            trip.participantIdsJson = json
        }

        if let planData = try? JSONSerialization.data(withJSONObject: plan),
           let planJson = String(data: planData, encoding: .utf8) {
            trip.aiProposalJson = planJson
        }

        if let legsJson = plan["legs"] as? [[String: Any]] {
            trip.legs = legsJson.map { legDict in
                KBTripLeg(
                    familyId: familyId,
                    tripId: trip.id,
                    order: legDict["order"] as? Int ?? 0,
                    fromLocation: legDict["fromLocation"] as? String ?? "",
                    toLocation: legDict["toLocation"] as? String ?? "",
                    transportModeRaw: legDict["transportMode"] as? String ?? "car",
                    notes: legDict["notes"] as? String
                )
            }
        }

        if let dayPlansJson = plan["dayPlans"] as? [[String: Any]] {
            let parsed = dayPlansJson.map { dayDict in
                let dayPlan = KBTripDayPlan(
                    familyId: familyId,
                    tripId: trip.id,
                    dateString: dayDict["date"] as? String ?? "",
                    location: dayDict["location"] as? String ?? "",
                    morningPlan: dayDict["morningPlan"] as? String ?? "",
                    afternoonPlan: dayDict["afternoonPlan"] as? String ?? "",
                    eveningPlan: dayDict["eveningPlan"] as? String ?? ""
                )
                dayPlan.accommodationName = dayDict["accommodationName"] as? String
                dayPlan.accommodationType = dayDict["accommodationType"] as? String
                dayPlan.accommodationCostPerNight = dayDict["accommodationCostPerNight"] as? Double
                dayPlan.weatherBackupPlan = dayDict["weatherBackupPlan"] as? String
                dayPlan.estimatedDailyCost = dayDict["estimatedDailyCost"] as? Double
                return dayPlan
            }
            trip.dayPlans = TravelItineraryBuilder.normalizeDayPlansForTrip(trip, parsedPlans: parsed, proposal: plan)
        }

        if let packingJson = plan["packingList"] as? [[String: Any]] {
            trip.packingItems = packingJson.map { itemDict in
                KBPackingItem(
                    familyId: familyId,
                    tripId: trip.id,
                    label: itemDict["label"] as? String ?? "",
                    categoryRaw: itemDict["category"] as? String ?? "other",
                    isAIGenerated: true,
                    fromMedicalProfile: itemDict["fromMedicalProfile"] as? Bool ?? false
                )
            }
        }

        modelContext.insert(trip)
        _ = TravelTripAlbumService.ensureAlbum(for: trip, modelContext: modelContext, userId: uid)
        _ = TravelTripNotesService.ensureNote(for: trip, modelContext: modelContext, userId: uid)

        do {
            try modelContext.save()
        } catch {
            generationError = "Salvataggio viaggio non riuscito. Riprova."
            return nil
        }

        acceptedTrip = trip

        Task { @MainActor in
            await tripRemote.syncTrip(trip)
        }

        return trip.id
    }

    func regenerateDayPlan(
        day: TravelItineraryDay,
        children: [KBChild],
        members: [KBFamilyMember],
        pediatricProfiles: [KBPediatricProfile]
    ) async {
        NSLog("[KidBox][Travel] regenerateDayPlan tapped dayIndex=\(day.dayIndex) date=\(day.dateString)")
        guard let familyId = coordinator.activeFamilyId, !familyId.isEmpty else {
            NSLog("[KidBox][Travel] regenerateDayPlan ABORT: no active family")
            generationError = "Famiglia attiva non disponibile."
            return
        }
        guard var current = proposalPlan else {
            NSLog("[KidBox][Travel] regenerateDayPlan ABORT: proposalPlan is nil")
            generationError = "Proposta corrente non disponibile."
            return
        }

        regeneratingDayIndex = day.dayIndex
        defer { regeneratingDayIndex = nil }

        let otherPlaces = TravelDayRegeneration.collectOtherDaysPlaces(from: current, excludingDate: day.dateString)
        let legs = TravelDayRegeneration.legsPayload(
            from: legs,
            tripLegs: [],
            fallbackLocation: day.location
        )
        let wizardData = TravelDayRegeneration.wizardData(
            tripName: tripName,
            day: day,
            budgetPerDay: budgetTotal / Double(max(tripDayCount, 1)),
            currency: currency,
            legs: legs
        )
        let prompt = TravelDayRegeneration.regenerationPrompt(day: day, otherPlaces: otherPlaces)
        let familyCtx = familyContextForAI(
            children: children,
            members: members,
            pediatricProfiles: pediatricProfiles
        )

        do {
            let response = try await aiService.generateTravelPlan(
                TravelPlanRequest(
                    wizardData: wizardData,
                    freeTextPrompt: prompt,
                    familyContext: familyCtx,
                    regenerateSingleDay: true
                ),
                familyId: familyId
            )
            guard let newDay = TravelDayRegeneration.extractRegeneratedDay(
                from: response,
                dateString: day.dateString
            ) else {
                let planDays = response.travelPlan.map { TravelJSONCoercion.dayPlans(from: $0).count } ?? 0
                KBLog.ai.kbError(
                    "regenerateDayPlan parse failed date=\(day.dateString) travelPlanDays=\(planDays) narrativeLen=\(response.narrativeText.count)"
                )
                generationError = "Rigenerazione giorno non riuscita: risposta AI non valida. Se persiste, ridistribuisci la Cloud Function generateTravelPlan."
                return
            }
            current = TravelDayRegeneration.mergeDay(into: current, newDay: newDay, dateString: day.dateString)
            proposalPlan = current
            proposalRevision += 1
            generationError = nil
            KBLog.ai.kbInfo("regenerateDayPlan merged day=\(day.dateString) revision=\(proposalRevision)")
        } catch let error as AIServiceError {
            generationError = error.errorDescription
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func familyContextForAI(
        children: [KBChild],
        members: [KBFamilyMember],
        pediatricProfiles: [KBPediatricProfile]
    ) -> [String: Any] {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        let selectedChildren = children.filter { selectedParticipantIds.contains($0.id) }
        let childrenContext: [[String: Any]] = selectedChildren.compactMap { child in
            guard let birthDate = child.birthDate else { return nil }
            let profile = pediatricProfiles.first { $0.childId == child.id }
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
            var dict: [String: Any] = [
                "name": child.name,
                "birthDate": fmt.string(from: birthDate),
                "age": age,
            ]
            if let allergies = profile?.allergies, !allergies.isEmpty { dict["allergies"] = allergies }
            if let notes = profile?.medicalNotes, !notes.isEmpty { dict["medicalNotes"] = notes }
            return dict
        }

        let participantNames = members
            .filter { selectedParticipantIds.contains($0.userId) }
            .compactMap(\.displayName)

        var familyContext: [String: Any] = [
            "children": childrenContext,
            "participants": participantNames,
            "participantSummary": selectedParticipantSummary(members: members, children: children),
        ]
        if let uid = coordinator.uid,
           let profile = TravelProfileStore.loadProfile(userId: uid) {
            familyContext["travelProfile"] = profile.familyContextValue()
        }
        if !tripStyles.isEmpty {
            familyContext["tripStyles"] = tripStyles.map(\.rawValue)
        }
        return familyContext
    }

    var refinementChatSeed: String {
        var text = "Sto pianificando il viaggio \"\(tripName)\" dal \(formattedShort(startDate)) al \(formattedShort(endDate))."
        if let narrative = proposalNarrative, !narrative.isEmpty {
            text += "\n\nProposta attuale:\n\(narrative.prefix(1200))"
        }
        text += "\n\nAiutami a modificare o migliorare questo itinerario."
        return text
    }

    private func formattedShort(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
