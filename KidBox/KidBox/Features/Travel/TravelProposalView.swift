//
//  TravelProposalView.swift
//  KidBox
//

import SwiftUI

struct TravelProposalView: View {

    @ObservedObject var vm: TravelPlanningViewModel
    let children: [KBChild]
    let pediatricProfiles: [KBPediatricProfile]
    let members: [KBFamilyMember]
    var onAccepted: (String) -> Void

    @ObservedObject private var subscriptionManager = KBSubscriptionManager.shared
    @State private var showChat = false
    @State private var showUpgrade = false
    @State private var isAccepting = false
    @State private var selectedStop: TravelItineraryStopContext?
    @State private var showRegenerateError = false

    private var aiAvailable: Bool { subscriptionManager.currentPlan.includesAI }
    private var hasProposalContent: Bool {
        vm.proposalPlan != nil
            || !(vm.proposalNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var showSubscriptionGate: Bool {
        !aiAvailable && !vm.isGenerating && !hasProposalContent
    }
    private let loadingIcons = ["✈️", "🏨", "🗺️", "💊", "🧳"]

    var body: some View {
        ZStack(alignment: .bottom) {
            if vm.regeneratingDayIndex != nil {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Rigenerazione giorno \(vm.regeneratingDayIndex ?? 0)…")
                        .font(.subheadline.weight(.medium))
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if vm.isGenerating {
                        generatingView
                    } else if let plan = vm.proposalPlan {
                        proposalContent(plan: plan)
                    } else if let err = vm.generationError {
                        Text(err).foregroundStyle(.red)
                    } else if let narrative = vm.proposalNarrative, !narrative.isEmpty {
                        GroupBox("Introduzione") {
                            Text(narrative).font(.body)
                        }
                        Text("L'itinerario strutturato non è disponibile. Prova «Rigenera».")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nessun risultato. Tocca «Rigenera» o riprova più tardi.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .padding(.bottom, 90)
            }

            if showSubscriptionGate {
                VStack(spacing: 12) {
                    Text("Piano Pro o Max richiesto per la pianificazione AI.")
                        .foregroundStyle(.secondary)
                    Button("Scopri Pro e Max") { showUpgrade = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if !vm.isGenerating && (vm.proposalPlan != nil || vm.generationError != nil || !(vm.proposalNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                actionBar
            }
        }
        .navigationTitle(vm.proposalPlan == nil ? vm.tripName : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.dailyLimit > 0, !vm.isGenerating {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(vm.usageToday)/\(vm.dailyLimit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            guard aiAvailable else { return }
            // Generazione avviata dal wizard; qui solo fallback se si apre la proposta senza passare dal bottone.
            if vm.proposalPlan == nil, vm.generationError == nil, !vm.isGenerating {
                await vm.generatePlan(
                    children: children,
                    pediatricProfiles: pediatricProfiles,
                    members: members
                )
            }
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
                .environmentObject(subscriptionManager)
        }
        .alert("Rigenerazione giorno", isPresented: $showRegenerateError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.generationError ?? "Operazione non riuscita.")
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                PlanningAIChatView(initialMessage: vm.refinementChatSeed)
            }
        }
        .navigationDestination(item: $selectedStop) { stop in
            TravelPlaceDetailView(context: stop, familyId: vm.activeFamilyId)
        }
    }

    private var generatingView: some View {
        TimelineView(.periodic(from: .now, by: 0.8)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 0.8) % loadingIcons.count
            VStack(spacing: 20) {
                Text(loadingIcons[index]).font(.system(size: 56))
                ProgressView()
                Text("L'AI sta pianificando il tuo viaggio…")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    private func proposalContent(plan: [String: Any]) -> some View {
        let participantIdsJson = encodeParticipantIds(vm.selectedParticipantIds)
        let overview = TravelItineraryBuilder.buildFromProposal(
            plan,
            tripName: vm.tripName,
            budgetLimit: vm.budgetTotal,
            currency: vm.currency,
            participantIdsJson: participantIdsJson,
            members: members,
            children: children,
            plannedDayCount: vm.tripDayCount
        )

        TravelItineraryDetailView(
            overview: overview,
            legs: [],
            introduction: vm.proposalNarrative,
            onStopTap: { stop in selectedStop = stop },
            onRegenerateDayTap: { day in
                Task {
                    await vm.regenerateDayPlan(
                        day: day,
                        children: children,
                        members: members,
                        pediatricProfiles: pediatricProfiles
                    )
                    if vm.generationError != nil {
                        showRegenerateError = true
                    }
                }
            },
            regeneratingDayId: overview.days.first { $0.dayIndex == vm.regeneratingDayIndex }?.id
        )
        .id(vm.proposalRevision)

        if let packing = plan["packingList"] as? [[String: Any]], !packing.isEmpty {
            Text("Da portare")
                .font(.title3.bold())
                .padding(.top, 8)
            ForEach(Array(packing.prefix(5).enumerated()), id: \.offset) { _, item in
                Label(item["label"] as? String ?? "", systemImage: "checkmark.circle")
            }
            if packing.count > 5 {
                Text("+ altri \(packing.count - 5) articoli")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let health = plan["healthNotes"] as? [String], !health.isEmpty {
            Text("Note salute")
                .font(.title3.bold())
                .padding(.top, 8)
            ForEach(health, id: \.self) { note in
                Text("• \(note)")
            }
        }

        if let emergency = plan["emergencyContacts"] as? [String: Any] {
            Text("Emergenze")
                .font(.title3.bold())
                .padding(.top, 8)
            emergencyCard(emergency)
        }
    }

    private func encodeParticipantIds(_ ids: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(Array(ids)),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func emergencyCard(_ emergency: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let country = emergency["country"] as? String { Text("Paese: \(country)") }
            if let num = emergency["emergencyNumber"] as? String { Text("Emergenze: \(num)") }
            if let embassy = emergency["italianEmbassy"] as? String { Text("Ambasciata: \(embassy)") }
            if let hospital = emergency["nearestHospital"] as? String { Text("Ospedale: \(hospital)") }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if aiAvailable {
                Button("Rigenera") {
                    Task {
                        await vm.regenerate(
                            children: children,
                            pediatricProfiles: pediatricProfiles,
                            members: members
                        )
                    }
                }
                .buttonStyle(.bordered)

                Button("Modifica") { showChat = true }
                    .buttonStyle(.bordered)
            }

            Button("Accetta ✓") {
                guard !isAccepting else { return }
                isAccepting = true
                if let tripId = vm.acceptProposal() {
                    onAccepted(tripId)
                }
                isAccepting = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAccepting || vm.proposalPlan == nil)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
