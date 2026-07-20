//
//  TravelWizardView.swift
//  KidBox
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct TravelWizardView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var subscriptionManager = KBSubscriptionManager.shared
    @State private var vm: TravelPlanningViewModel?
    @State private var step = 0
    @State private var showProposal = false
    @State private var showUpgrade = false

    private var aiAvailable: Bool { subscriptionManager.currentPlan.includesAI }

    @Query private var members: [KBFamilyMember]
    @Query private var children: [KBChild]
    @Query private var pediatricProfiles: [KBPediatricProfile]

    private let familyId: String
    private let prefillDestinationName: String?
    private let onTripAccepted: ((String) -> Void)?

    private let totalSteps = TravelPlanningViewModel.totalWizardSteps

    init(
        familyId: String,
        prefillDestinationName: String? = nil,
        onTripAccepted: ((String) -> Void)? = nil
    ) {
        self.familyId = familyId
        self.prefillDestinationName = prefillDestinationName
        self.onTripAccepted = onTripAccepted
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: [SortDescriptor(\KBFamilyMember.displayName)]
        )
        _children = Query(
            filter: #Predicate<KBChild> { $0.familyId == fid },
            sort: [SortDescriptor(\KBChild.name)]
        )
        _pediatricProfiles = Query(
            filter: #Predicate<KBPediatricProfile> { $0.familyId == fid }
        )
    }

    var body: some View {
        Group {
            if let vm {
                NavigationStack {
                    TravelWizardRootView(
                        vm: vm,
                        step: $step,
                        showProposal: $showProposal,
                        showUpgrade: $showUpgrade,
                        members: members,
                        children: children,
                        pediatricProfiles: pediatricProfiles,
                        familyId: familyId,
                        totalSteps: totalSteps,
                        aiAvailable: aiAvailable,
                        onTripAccepted: onTripAccepted,
                        onDismiss: { dismiss() }
                    )
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if vm == nil {
                let model = TravelPlanningViewModel(modelContext: modelContext, coordinator: coordinator)
                if let place = prefillDestinationName, !place.isEmpty {
                    model.applyPrefill(destination: place)
                }
                if let uid = coordinator.uid {
                    model.loadTripStylesFromProfile(userId: uid)
                }
                vm = model
            }
        }
    }
}

// MARK: - Root (ObservedObject so Continue button reacts to wizard state)

private struct TravelWizardRootView: View {
    @ObservedObject var vm: TravelPlanningViewModel
    @Binding var step: Int
    @Binding var showProposal: Bool
    @Binding var showUpgrade: Bool
    let members: [KBFamilyMember]
    let children: [KBChild]
    let pediatricProfiles: [KBPediatricProfile]
    let familyId: String
    let totalSteps: Int
    let aiAvailable: Bool
    let onTripAccepted: ((String) -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        TravelWizardStepLayout(
            step: step,
            totalSteps: totalSteps,
            title: stepTitle,
            subtitle: stepSubtitle,
            canContinue: vm.canProceed(step: step, members: members, children: children)
                && (step < totalSteps - 1 || (aiAvailable && vm.canGenerate)),
            continueTitle: step == totalSteps - 1 ? "Crea il mio piano" : "Continua",
            onBack: {
                travelWizardDismissKeyboard()
                withAnimation { step -= 1 }
            },
            onContinue: {
                travelWizardDismissKeyboard()
                advance()
            }
        ) {
            stepContent()
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: Binding(
            get: { vm.isGenerating },
            set: { _ in }
        )) {
            TravelPlanningLoadingView(
                destinationName: vm.destinationName.isEmpty ? NSLocalizedString("il viaggio", comment: "") : vm.destinationName,
                subtitle: String(format: NSLocalizedString("Sto finalizzando il percorso di %d giorni", comment: ""), vm.tripDayCount),
                plannedDayCount: vm.tripDayCount
            )
            .interactiveDismissDisabled(true)
        }
        .navigationDestination(isPresented: $showProposal) {
            TravelProposalView(
                vm: vm,
                children: children,
                pediatricProfiles: pediatricProfiles,
                members: members,
                onAccepted: { tripId in
                    showProposal = false
                    if let onTripAccepted {
                        onTripAccepted(tripId)
                    } else {
                        onDismiss()
                    }
                }
            )
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
                .environmentObject(KBSubscriptionManager.shared)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla", action: onDismiss)
            }
        }
        .travelWizardKeyboardDismiss()
    }

    private var stepTitle: LocalizedStringKey {
        switch step {
        case 0: return "Dove vuoi andare?"
        case 1: return "Quando è il tuo viaggio?"
        case 2: return "Come ci arriverete?"
        case 3: return "Chi viaggia?"
        case 4: return "Qual è il tuo budget?"
        case 5: return "Qual è il mood di questo viaggio?"
        default: return "Crea il tuo piano"
        }
    }

    private var stepSubtitle: LocalizedStringKey {
        switch step {
        case 0: return "Cerca la destinazione del viaggio"
        case 1: return "Scegli le date del viaggio"
        case 2: return "Scegli come viaggerete"
        case 3: return "Definisce tutto il piano"
        case 4: return "Costo totale del viaggio"
        case 5:
            let place = vm.destinationName
            return place.isEmpty ? "Ogni viaggio è diverso" : "Personalizza per \(place)"
        default: return "Verifica e genera con l'AI"
        }
    }

    @ViewBuilder
    private func stepContent() -> some View {
        switch step {
        case 0: TravelWizardDestinationStep(vm: vm)
        case 1: TravelWizardDatesStep(vm: vm)
        case 2: TravelWizardTransportStep(vm: vm)
        case 3: TravelWizardParticipantsStep(vm: vm, members: members, children: children)
        case 4: TravelWizardBudgetStep(vm: vm, members: members, children: children)
        case 5: TravelWizardTripStyleStep(vm: vm, destinationName: vm.destinationName)
        default:
            TravelWizardBuildStep(
                vm: vm,
                members: members,
                children: children,
                aiAvailable: aiAvailable,
                onUpgrade: { showUpgrade = true }
            )
        }
    }

    private func advance() {
        vm.syncTripFromWizardInputs()
        if step < totalSteps - 1 {
            withAnimation { step += 1 }
            return
        }
        guard aiAvailable else {
            showUpgrade = true
            return
        }
        Task { @MainActor in
            await vm.generatePlan(
                children: children,
                pediatricProfiles: pediatricProfiles,
                members: members
            )
            let narrative = (vm.proposalNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPlan = vm.proposalPlan != nil
            let hasNarrative = !narrative.isEmpty
            let hasError = vm.generationError != nil
            if !hasPlan && !hasNarrative && !hasError {
                vm.generationError = "Risposta vuota dal server. Controlla la connessione e riprova."
            }
            let shouldShowProposal =
                vm.proposalPlan != nil
                || !(vm.proposalNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || vm.generationError != nil
            if shouldShowProposal {
                try? await Task.sleep(for: .milliseconds(150))
                showProposal = true
            }
        }
    }
}

private func travelWizardDismissKeyboard() {
#if canImport(UIKit)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
#endif
}

private extension View {
    func travelWizardKeyboardDismiss() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") {
                        travelWizardDismissKeyboard()
                    }
                }
            }
    }
}
