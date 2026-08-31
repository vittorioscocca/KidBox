//
//  TravelListView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog

struct TravelListView: View {

    let familyId: String

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = KBSubscriptionManager.shared
    @Query private var trips: [KBTrip]
    @Query private var tripLegs: [KBTripLeg]
    @State private var showWizard = false
    @State private var showUpgrade = false
    @State private var needsOnboarding: Bool?

    /// Il pianificatore viaggi è incluso nei soli piani a pagamento: `isAIAccessible`
    /// da solo non basta, perché è false solo per i Free che hanno già esaurito il
    /// bonus una tantum — un Free con bonus intatto riuscirebbe a generare itinerari.
    private var aiAvailable: Bool { subscriptionManager.currentPlan != .free }
    private var travelProfile: TravelProfile? {
        TravelProfileStore.loadProfile(userId: userId)
    }

    private var userId: String {
        coordinator.uid ?? Auth.auth().currentUser?.uid ?? ""
    }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _trips = Query(
            filter: #Predicate<KBTrip> { $0.familyId == fid },
            sort: [SortDescriptor(\KBTrip.startDate, order: .reverse)]
        )
        _tripLegs = Query(
            filter: #Predicate<KBTripLeg> { $0.familyId == fid },
            sort: [SortDescriptor(\KBTripLeg.order)]
        )
    }

    private var legsByTripId: [String: [KBTripLeg]] {
        Dictionary(grouping: tripLegs, by: \.tripId)
            .mapValues { $0.sorted { $0.order < $1.order } }
    }

    /// Ultimi tre viaggi (più recenti per data di inizio).
    private var recentTrips: [KBTrip] {
        Array(trips.prefix(3))
    }

    /// Piano bloccato (Free): stessa forma della `lockedCard` del Piano Alimentare.
    private var travelLockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Incluso in Pro e Max", systemImage: "lock.fill")
                .font(.subheadline.bold())
            Text("Passa a Pro o Max per pianificare viaggi con l'AI.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showUpgrade = true
                AppAnalytics.aiPaywallShown(context: "travel_locked_card")
            } label: {
                Text("Scopri i piani")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KBTheme.cardBackground(colorScheme))
        )
    }

    var body: some View {
        Group {
            if needsOnboarding == true {
                // Su Free l'avviso va messo qui, non nella lista: la configurazione
                // iniziale è la prima schermata dei Viaggi, e senza avviso l'utente
                // risponde a tre domande per poi scoprire di non poter pianificare.
                TravelOnboardingView(
                    onComplete: { profile in
                        TravelProfileStore.save(profile: profile, userId: userId)
                        needsOnboarding = false
                    },
                    lockedNotice: aiAvailable ? nil : AnyView(travelLockedCard)
                )
            } else if needsOnboarding == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        TravelHubView(
                            familyId: familyId,
                            profile: travelProfile,
                            aiAvailable: aiAvailable,
                            onPlanTrip: {
                                if aiAvailable {
                                    showWizard = true
                                } else {
                                    showUpgrade = true
                                    AppAnalytics.aiPaywallShown(context: "travel_plan_trip")
                                }
                            },
                            onDiscover: {
                                if aiAvailable {
                                    coordinator.navigate(to: .travelDiscover(familyId: familyId))
                                } else {
                                    showUpgrade = true
                                    AppAnalytics.aiPaywallShown(context: "travel_discover")
                                }
                            }
                        )
                        .padding(.horizontal, 16)

                        if !trips.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                Text("I tuoi viaggi")
                                    .font(.title3.bold())
                                Spacer(minLength: 12)
                                Button("Vedi tutti") {
                                    coordinator.navigate(to: .travelAllTrips(familyId: familyId))
                                }
                                .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 16)

                            LazyVStack(spacing: 16) {
                                ForEach(recentTrips) { trip in
                                    let legs = legsByTripId[trip.id] ?? []
                                    Button {
                                        KBLog.navigation.kbDebug("TravelList: open trip id=\(trip.id)")
                                        coordinator.navigate(to: .travelTripDetail(familyId: familyId, tripId: trip.id))
                                    } label: {
                                        TravelTripCardView(trip: trip, legs: legs)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Stessa carta del Piano Alimentare: dire che serve un
                        // piano a pagamento senza dare il modo di arrivarci
                        // lasciava l'utente in un vicolo cieco.
                        if !aiAvailable {
                            travelLockedCard
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .kbRefreshable {
                    await SyncCenter.shared.forceRefresh(modelContext: modelContext) {
                        SyncCenter.shared.stopTripsRealtime()
                        SyncCenter.shared.startTripsRealtime(familyId: familyId, modelContext: modelContext)
                    }
                }
                .background(KBTheme.background(colorScheme))
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle(needsOnboarding == true ? "" : "Viaggi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if needsOnboarding != true {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showWizard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        // La barra resta visibile anche durante la configurazione iniziale: senza,
        // non c'era alcun modo di uscire da Viaggi (niente «Indietro»).
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showWizard) {
            TravelWizardView(
                familyId: familyId,
                onTripAccepted: { tripId in
                    showWizard = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        coordinator.navigate(to: .travelTripDetail(familyId: familyId, tripId: tripId))
                    }
                }
            )
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(triggerFeature: "travel_lock")
                .environmentObject(subscriptionManager)
        }
        .onAppear {
            refreshOnboardingGate()
        }
        .onChange(of: userId) { _, _ in
            refreshOnboardingGate()
        }
    }

    private func refreshOnboardingGate() {
        if userId.isEmpty {
            needsOnboarding = false
        } else {
            needsOnboarding = !TravelProfileStore.hasCompletedOnboarding(userId: userId)
        }
    }
}
