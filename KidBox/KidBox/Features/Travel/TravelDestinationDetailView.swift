//
//  TravelDestinationDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct TravelDestinationDetailView: View {

    let destination: TravelDestination
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var members: [KBFamilyMember]
    @Query private var children: [KBChild]

    @State private var showWizard = false
    @State private var isAccepting = false
    @State private var acceptError: String?

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    private var hasStructuredPreview: Bool { destination.hasStructuredAiPreview }

    private var overview: TravelItineraryOverview {
        TravelItineraryBuilder.buildFromSuggestion(destination)
    }

    private var introduction: String {
        var parts: [String] = []
        if !destination.aiHeadline.isEmpty {
            parts.append(destination.aiHeadline)
        }
        if !destination.whyForYou.isEmpty {
            parts.append(destination.whyForYou)
        }
        return parts.joined(separator: "\n\n")
    }

    init(destination: TravelDestination, familyId: String) {
        self.destination = destination
        self.familyId = familyId
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: [SortDescriptor(\KBFamilyMember.displayName)]
        )
        _children = Query(
            filter: #Predicate<KBChild> { $0.familyId == fid },
            sort: [SortDescriptor(\KBChild.name)]
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TravelItineraryDetailView(
                        overview: overview,
                        legs: [],
                        introduction: introduction,
                        contentHorizontalPadding: 22
                    )

                    briefChips
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    Text(footerCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, hasStructuredPreview ? 120 : 100)
                }
            }

            bottomActions
        }
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWizard) {
            TravelWizardView(
                familyId: familyId,
                prefillDestinationName: destination.name,
                onTripAccepted: { _ in showWizard = false }
            )
        }
        .alert("Errore", isPresented: Binding(
            get: { acceptError != nil },
            set: { if !$0 { acceptError = nil } }
        )) {
            Button("OK", role: .cancel) { acceptError = nil }
        } message: {
            Text(acceptError ?? "")
        }
    }

    private var footerCaption: String {
        if hasStructuredPreview {
            return "Itinerario AI pronto: accetta per salvare il viaggio pianificato con giorni e tappe già impostati."
        }
        return "Anteprima generata dall'AI in base al tuo profilo. Personalizza date, budget e viaggiatori nel passo successivo."
    }

    private var briefChips: some View {
        HStack(spacing: 10) {
            chip(icon: "calendar", text: destination.durationDays + " giorni")
            chip(icon: "eurosign.circle", text: destination.estimatedCost)
            chip(icon: "sun.max", text: destination.bestTime)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button {
                if hasStructuredPreview {
                    acceptStructuredPreview()
                } else {
                    showWizard = true
                }
            } label: {
                Group {
                    if isAccepting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(hasStructuredPreview ? "Accetta viaggio ✓" : "Pianifica questo viaggio")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accent.opacity(isAccepting ? 0.7 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAccepting)

            if hasStructuredPreview {
                Button("Personalizza date e viaggiatori") {
                    showWizard = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accent)
                .disabled(isAccepting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func acceptStructuredPreview() {
        guard !isAccepting else { return }
        isAccepting = true
        defer { isAccepting = false }

        let vm = TravelPlanningViewModel(modelContext: modelContext, coordinator: coordinator)
        guard let tripId = vm.acceptPreviewFromSuggestion(
            destination: destination,
            familyId: familyId,
            members: members,
            children: children
        ) else {
            acceptError = vm.generationError ?? "Salvataggio non riuscito."
            return
        }

        if !coordinator.path.isEmpty {
            coordinator.navigateBack()
        }
        if !coordinator.path.isEmpty {
            coordinator.navigateBack()
        }
        coordinator.navigate(to: .travelTripDetail(familyId: familyId, tripId: tripId))
    }
}
