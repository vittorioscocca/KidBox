//
//  TravelDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct TravelDetailView: View {

    let tripId: String
    let familyId: String

    @Query private var trips: [KBTrip]
    @Query private var dayPlans: [KBTripDayPlan]
    @Query private var legs: [KBTripLeg]
    @Query private var members: [KBFamilyMember]
    @Query private var children: [KBChild]
    @Query private var pediatricProfiles: [KBPediatricProfile]
    @Query private var familyPhotos: [KBFamilyPhoto]
    @Query private var familyNotes: [KBNote]
    @Query private var todoLists: [KBTodoList]
    @Query private var todoItems: [KBTodoItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var showDeleteTripConfirmation = false
    @State private var categoryResults: TravelCategoryResultsPresentation?
    @State private var tripPhotoAlbumRoute: TripPhotoAlbumRoute?
    @State private var tripNoteRoute: TripNoteRoute?
    @State private var tripTodoRoute: TripTodoRoute?
    @State private var tripExpensesRoute: TripExpensesRoute?
    @State private var selectedStop: TravelItineraryStopContext?
    @State private var regeneratingDayId: String?
    @State private var dayRegenerateError: String?
    @State private var itineraryRefreshToken = UUID()
    @State private var localProposalJsonOverride: String?
    @State private var dayRegenerateSuccessMessage: String?

    init(tripId: String, familyId: String) {
        self.tripId = tripId
        self.familyId = familyId
        let tid = tripId
        let fid = familyId
        _trips = Query(filter: #Predicate<KBTrip> { $0.id == tid && $0.familyId == fid })
        _dayPlans = Query(
            filter: #Predicate<KBTripDayPlan> { $0.tripId == tid && $0.familyId == fid },
            sort: [SortDescriptor(\KBTripDayPlan.dateString)]
        )
        _legs = Query(
            filter: #Predicate<KBTripLeg> { $0.tripId == tid && $0.familyId == fid },
            sort: [SortDescriptor(\KBTripLeg.order)]
        )
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted })
        _children = Query(filter: #Predicate<KBChild> { $0.familyId == fid })
        _pediatricProfiles = Query(filter: #Predicate<KBPediatricProfile> { $0.familyId == fid })
        _familyPhotos = Query(
            filter: #Predicate<KBFamilyPhoto> { $0.familyId == fid && !$0.isDeleted },
            sort: [SortDescriptor(\KBFamilyPhoto.takenAt, order: .reverse)]
        )
        _familyNotes = Query(
            filter: #Predicate<KBNote> { $0.familyId == fid && !$0.isDeleted },
            sort: [SortDescriptor(\KBNote.updatedAt, order: .reverse)]
        )
        _todoLists = Query(filter: #Predicate<KBTodoList> { $0.familyId == fid && !$0.isDeleted })
        _todoItems = Query(
            filter: #Predicate<KBTodoItem> { $0.familyId == fid && !$0.isDeleted },
            sort: [SortDescriptor(\KBTodoItem.updatedAt, order: .reverse)]
        )
    }

    private var trip: KBTrip? { trips.first }

    private var travelExpenseCategoryId: String {
        KBExpenseCategory.defaultCategoryId(familyId: familyId, slug: "viaggi")
    }

    private var primaryChildId: String? {
        children.first(where: { !$0.isDeleted })?.id
    }

    var body: some View {
        Group {
            if let trip {
                itineraryContent(for: trip)
                    .navigationTitle(trip.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showDeleteTripConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Elimina viaggio")
                        }
                    }
                    .alert(
                        "Rigenerazione non riuscita",
                        isPresented: Binding(
                            get: { dayRegenerateError != nil },
                            set: { if !$0 { dayRegenerateError = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) { dayRegenerateError = nil }
                    } message: {
                        Text(dayRegenerateError ?? "")
                    }
                    .alert(
                        "Giorno aggiornato",
                        isPresented: Binding(
                            get: { dayRegenerateSuccessMessage != nil },
                            set: { if !$0 { dayRegenerateSuccessMessage = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) { dayRegenerateSuccessMessage = nil }
                    } message: {
                        Text(dayRegenerateSuccessMessage ?? "")
                    }
                    .confirmationDialog(
                        "Eliminare questo viaggio?",
                        isPresented: $showDeleteTripConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Elimina", role: .destructive) {
                            deleteTrip(trip)
                        }
                        Button("Annulla", role: .cancel) {}
                    } message: {
                        Text("Itinerario, packing list e note collegate verranno rimossi da questo dispositivo.")
                    }
                    .navigationDestination(item: $categoryResults) { presentation in
                        TravelCategoryResultsView(
                            title: presentation.title,
                            emoji: presentation.emoji,
                            items: presentation.items,
                            familyId: familyId,
                            destinationTitle: presentation.destinationTitle
                        )
                    }
                    .navigationDestination(item: $tripPhotoAlbumRoute) { route in
                        PhotoAlbumDetailView(
                            familyId: familyId,
                            albumId: route.albumId,
                            albumTitle: route.albumTitle,
                            showTripDedicatedBanner: true
                        )
                    }
                    .navigationDestination(item: $selectedStop) { stop in
                        TravelPlaceDetailView(context: stop, familyId: familyId)
                    }
                    .navigationDestination(item: $tripNoteRoute) { route in
                        NoteDetailView(
                            familyId: familyId,
                            noteId: route.noteId,
                            focusBodyOnAppear: route.focusBodyOnAppear
                        )
                    }
                    .navigationDestination(item: $tripTodoRoute) { route in
                        TodoListView(
                            familyId: familyId,
                            childId: route.childId,
                            listId: route.listId
                        )
                    }
                    .navigationDestination(item: $tripExpensesRoute) { route in
                        ExpensesHomeView(
                            familyId: familyId,
                            initialCategoryId: route.categoryId
                        )
                    }
                    .task(id: trip.id) {
                        guard let uid = coordinator.uid else { return }
                        let name = members.first(where: { $0.userId == uid })?.displayName ?? ""
                        TravelTripAlbumService.ensureAlbum(for: trip, modelContext: modelContext, userId: uid)
                        TravelTripNotesService.ensureNote(
                            for: trip,
                            modelContext: modelContext,
                            userId: uid,
                            userDisplayName: name
                        )
                        if let childId = primaryChildId {
                            TravelTripTodoService.ensureList(
                                for: trip,
                                childId: childId,
                                modelContext: modelContext
                            )
                        }
                    }
            } else {
                ContentUnavailableView("Viaggio non trovato", systemImage: "exclamationmark.triangle")
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
    }

    @ViewBuilder
    private func itineraryContent(for trip: KBTrip) -> some View {
        let overview = TravelItineraryBuilder.build(
            trip: trip,
            dayPlans: dayPlans,
            legs: legs,
            members: members,
            children: children,
            proposalOverride: localProposalJsonOverride.flatMap { TravelJSONCoercion.dictionary($0) }
        )
        if overview.days.isEmpty {
            ScrollView {
                ContentUnavailableView(
                    "Nessun giorno pianificato",
                    systemImage: "calendar",
                    description: Text("L'itinerario giornaliero non è disponibile per questo viaggio.")
                )
                .padding(.top, 40)

                tripExtrasSection(for: trip)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
            }
            .background(KBTheme.background(colorScheme))
        } else {
            let hotels = TravelItineraryBuilder.collectHotels(dayPlans: dayPlans, overview: overview)
            let restaurants = TravelItineraryBuilder.collectRestaurants(
                dayPlans: dayPlans,
                overview: overview,
                proposalJson: trip.aiProposalJson
            )
            let activities = TravelItineraryBuilder.collectActivities(
                dayPlans: dayPlans,
                overview: overview,
                proposalJson: trip.aiProposalJson
            )

            ZStack {
            ScrollView {
                TravelItineraryDetailView(
                    overview: overview,
                    legs: legs,
                    hotelsCount: hotels.count,
                    restaurantsCount: restaurants.count,
                    activitiesCount: activities.count,
                    onHotelsTap: {
                        categoryResults = TravelCategoryResultsPresentation(
                            title: "Hotel",
                            emoji: "🛏️",
                            items: hotels,
                            destinationTitle: overview.destinationTitle
                        )
                    },
                    onRestaurantsTap: {
                        categoryResults = TravelCategoryResultsPresentation(
                            title: "Ristoranti",
                            emoji: "🍽️",
                            items: restaurants,
                            destinationTitle: overview.destinationTitle
                        )
                    },
                    onActivitiesTap: {
                        categoryResults = TravelCategoryResultsPresentation(
                            title: "Attività",
                            emoji: "🎯",
                            items: activities,
                            destinationTitle: overview.destinationTitle
                        )
                    },
                    onStopTap: { stop in
                        selectedStop = stop
                    },
                    onRegenerateDayTap: { day in
                        regenerateDay(day, trip: trip)
                    },
                    regeneratingDayId: regeneratingDayId
                )
                .id(itineraryRefreshToken)

                tripExtrasSection(for: trip)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            if regeneratingDayId != nil {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Rigenerazione giorno in corso…")
                        .font(.subheadline.weight(.medium))
                    Text("L'AI può impiegare fino a 90 secondi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            }
            .background(KBTheme.background(colorScheme))
        }
    }

    @ViewBuilder
    private func tripExtrasSection(for trip: KBTrip) -> some View {
        let albumId = trip.photoAlbumId ?? ""
        let photoCount = albumId.isEmpty ? 0 : TravelTripAlbumService.photoCount(albumId: albumId, in: familyPhotos)
        let noteTitle = TravelTripNotesService.defaultNoteTitle(for: trip)
        let noteId = trip.notesNoteId ?? ""
        let noteHasContent = !noteId.isEmpty && TravelTripNotesService.hasUserContent(noteId: noteId, in: familyNotes)
        let listName = TravelTripTodoService.defaultListName(for: trip)
        let todoListId = trip.todoListId ?? ""
        let openTodoCount = todoListId.isEmpty
            ? 0
            : TravelTripTodoService.openTodoCount(listId: todoListId, in: todoItems)

        VStack(spacing: 10) {
            TravelTripPhotosSection(photoCount: photoCount) {
                openTripPhotos(for: trip)
            }

            TravelTripNotesSection(noteTitle: noteTitle, hasContent: noteHasContent) {
                openTripNote(for: trip)
            }

            TravelTripTodosSection(listName: listName, openCount: openTodoCount) {
                openTripTodos(for: trip)
            }

            TravelTripExpensesSection {
                tripExpensesRoute = TripExpensesRoute(categoryId: travelExpenseCategoryId)
            }
        }
    }

    private func openTripPhotos(for trip: KBTrip) {
        guard let uid = coordinator.uid else { return }
        guard let resolvedAlbumId = TravelTripAlbumService.ensureAlbum(
            for: trip,
            modelContext: modelContext,
            userId: uid
        ) else { return }
        tripPhotoAlbumRoute = TripPhotoAlbumRoute(
            albumId: resolvedAlbumId,
            albumTitle: TravelTripAlbumService.defaultAlbumTitle(for: trip)
        )
    }

    private func openTripNote(for trip: KBTrip) {
        guard let uid = coordinator.uid else { return }
        let name = members.first(where: { $0.userId == uid })?.displayName ?? ""
        let existingId = trip.notesNoteId
        let hadContent = existingId.map { TravelTripNotesService.hasUserContent(noteId: $0, in: familyNotes) } ?? false
        guard let noteId = TravelTripNotesService.ensureNote(
            for: trip,
            modelContext: modelContext,
            userId: uid,
            userDisplayName: name
        ) else { return }
        tripNoteRoute = TripNoteRoute(noteId: noteId, focusBodyOnAppear: !hadContent)
    }

    private func openTripTodos(for trip: KBTrip) {
        guard let childId = primaryChildId else { return }
        guard let listId = TravelTripTodoService.ensureList(
            for: trip,
            childId: childId,
            modelContext: modelContext
        ) else { return }
        let resolvedChildId = TravelTripTodoService.childId(
            forListId: listId,
            familyId: familyId,
            in: todoLists
        ) ?? childId
        tripTodoRoute = TripTodoRoute(childId: resolvedChildId, listId: listId)
    }

    private func regenerateDay(_ day: TravelItineraryDay, trip: KBTrip) {
        NSLog("[KidBox][Travel] regenerateDay tapped tripId=\(trip.id) dayIndex=\(day.dayIndex) date=\(day.dateString)")
        guard let familyId = coordinator.activeFamilyId, !familyId.isEmpty else {
            NSLog("[KidBox][Travel] regenerateDay ABORT: no active family")
            dayRegenerateError = "Famiglia attiva non disponibile."
            return
        }
        regeneratingDayId = day.id
        dayRegenerateError = nil
        Task { @MainActor in
            defer {
                regeneratingDayId = nil
                NSLog("[KidBox][Travel] regenerateDay finished date=\(day.dateString)")
            }
            let otherPlaces = TravelDayRegeneration.collectOtherDaysPlaces(
                from: trip.aiProposalJson,
                excludingDate: day.dateString
            )
            let dayCount = max(dayPlans.count, 1)
            let legsPayload = TravelDayRegeneration.legsPayload(
                from: [],
                tripLegs: legs,
                fallbackLocation: day.location
            )
            let wizardData = TravelDayRegeneration.wizardData(
                tripName: trip.name,
                day: day,
                budgetPerDay: trip.budgetTotal / Double(dayCount),
                currency: trip.currency,
                legs: legsPayload
            )
            let prompt = TravelDayRegeneration.regenerationPrompt(day: day, otherPlaces: otherPlaces)
            let familyCtx = familyContextForTripRegeneration()

            do {
                let response = try await AIService.shared.generateTravelPlan(
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
                        "regenerateDay parse failed date=\(day.dateString) travelPlanDays=\(planDays) narrativeLen=\(response.narrativeText.count)"
                    )
                    dayRegenerateError = "Rigenerazione giorno non riuscita: risposta AI non valida."
                    return
                }
                let mStops = TravelJSONCoercion.arrayOfDictionaries(newDay["morningStops"])
                let aStops = TravelJSONCoercion.arrayOfDictionaries(newDay["afternoonStops"])
                let eStops = TravelJSONCoercion.arrayOfDictionaries(newDay["eveningStops"])
                if let firstStop = mStops.first {
                    NSLog("[KidBox][Travel] regenerateDay newDay morningStops[0] keys=\(Array(firstStop.keys)) dump=\(firstStop)")
                }
                NSLog("[KidBox][Travel] regenerateDay newDay top-level keys=\(Array(newDay.keys)) location=\(newDay["location"] ?? "nil") morningPlan=\((newDay["morningPlan"] as? String)?.prefix(80) ?? "nil")")
                KBLog.ai.kbInfo("regenerateDay success date=\(day.dateString) morningStops=\(mStops.count) afternoonStops=\(aStops.count) eveningStops=\(eStops.count)")

                if let plan = dayPlans.first(where: { $0.dateString == day.dateString }) {
                    TravelDayRegeneration.applyDayToModel(plan, from: newDay, fallbackLocation: day.location)
                }
                if let updatedJson = TravelDayRegeneration.mergeDay(
                    into: trip.aiProposalJson,
                    newDay: newDay,
                    dateString: day.dateString
                ) {
                    trip.aiProposalJson = updatedJson
                    localProposalJsonOverride = updatedJson
                    NSLog("[KidBox][Travel] localProposalJsonOverride set len=\(updatedJson.count)")
                }
                trip.updatedAt = Date()
                try modelContext.save()
                itineraryRefreshToken = UUID()
                dayRegenerateSuccessMessage = "Giorno \(day.dayIndex) rigenerato"
                await TripRemoteStore().syncTrip(
                    trip,
                    legs: legs,
                    dayPlans: dayPlans
                )
            } catch {
                dayRegenerateError = error.localizedDescription
                KBLog.ai.kbError("regenerateDay failed: \(error.localizedDescription)")
            }
        }
    }

    private func familyContextForTripRegeneration() -> [String: Any] {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let activeChildren = children.filter { !$0.isDeleted }
        let childrenContext: [[String: Any]] = activeChildren.compactMap { child in
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
        let participantNames = members.compactMap(\.displayName)
        var ctx: [String: Any] = [
            "children": childrenContext,
            "participants": participantNames,
        ]
        if let uid = coordinator.uid,
           let profile = TravelProfileStore.loadProfile(userId: uid) {
            ctx["travelProfile"] = profile.familyContextValue()
        }
        return ctx
    }

    private func deleteTrip(_ trip: KBTrip) {
        Task {
            await TripRemoteStore().deleteTrip(trip, modelContext: modelContext)
            await MainActor.run {
                coordinator.navigateBack()
            }
        }
    }
}

private struct TripPhotoAlbumRoute: Identifiable, Hashable {
    let albumId: String
    let albumTitle: String

    var id: String { albumId }
}

private struct TripNoteRoute: Identifiable, Hashable {
    let noteId: String
    let focusBodyOnAppear: Bool

    var id: String { noteId }
}

private struct TripTodoRoute: Identifiable, Hashable {
    let childId: String
    let listId: String

    var id: String { listId }
}

private struct TripExpensesRoute: Identifiable, Hashable {
    let categoryId: String

    var id: String { categoryId }
}
