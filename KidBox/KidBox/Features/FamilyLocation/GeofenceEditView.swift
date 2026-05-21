//
//  GeofenceEditView.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import Combine
import FirebaseAuth

/// Creazione o modifica di una zona geofence (sheet senza NavigationStack annidato).
struct GeofenceEditView: View {

    let familyId: String
    var existing: KBGeofence?
    let isOwner: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query private var familyMembers: [KBFamilyMember]

    @StateObject private var searchVM = GeofenceAddressSearchVM()

    @State private var name: String = ""
    @State private var selectedPresetEmoji: String = "🏫"
    @State private var customEmoji: String = ""
    @State private var useCustomEmoji = false

    @State private var latitude: Double = 41.9028
    @State private var longitude: Double = 12.4964
    @State private var radius: Double = 200

    @State private var notifyOnArrive = true
    @State private var notifyOnLeave = false

    @State private var monitorAllMembers = true
    @State private var monitoredUserIds: Set<String> = []
    @State private var notifyAllMembers = true
    @State private var notifyUserIds: Set<String> = []
    @State private var showMonitorPicker = false
    @State private var showNotifyPicker = false

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isSaving = false
    @State private var showSuggestions = false

    @FocusState private var searchFocused: Bool

    private let remote = GeofenceRemoteStore()

    private static let presetEmojis = ["🏫", "🏠", "🏥", "🏋️", "⛪", "🛒", "🏖️", "🌳"]

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.18)
            : Color(.systemBackground)
    }

    private var resolvedEmoji: String {
        if useCustomEmoji {
            let c = customEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? selectedPresetEmoji : String(c.prefix(1))
        }
        return selectedPresetEmoji
    }

    private var canSave: Bool {
        isOwner &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) &&
        (monitorAllMembers || !monitoredUserIds.isEmpty) &&
        (notifyAllMembers || !notifyUserIds.isEmpty)
    }

    private var isEditing: Bool { existing != nil }

    init(familyId: String, existing: KBGeofence?, isOwner: Bool) {
        self.familyId = familyId
        self.existing = existing
        self.isOwner = isOwner
        let fid = familyId
        _familyMembers = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBFamilyMember.displayName, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    emojiSection
                    mapSection
                    radiusSection
                    monitorSection
                    notifyRecipientsSection
                    notifyWhenSection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .onAppear {
            SyncCenter.shared.startMembersRealtime(familyId: familyId, modelContext: modelContext)
            loadExistingIfNeeded()
            updateCamera(animated: false)
        }
        .sheet(isPresented: $showMonitorPicker) {
            GeofenceMemberPickerSheet(
                navigationTitle: "Chi monitorare",
                sectionTitle: "Membri",
                footer: "Sul telefono di ogni persona selezionata, con posizione condivisa attiva, KidBox rileva entrata e uscita da questa zona.",
                useAllMembers: $monitorAllMembers,
                selectedUserIds: $monitoredUserIds,
                members: familyMembers
            )
        }
        .sheet(isPresented: $showNotifyPicker) {
            GeofenceMemberPickerSheet(
                navigationTitle: "Chi avvisare",
                sectionTitle: "Destinatari",
                footer: "Riceveranno una notifica push quando qualcuno entra o esce (secondo le opzioni sotto). Chi genera l'evento non riceve la propria notifica.",
                useAllMembers: $notifyAllMembers,
                selectedUserIds: $notifyUserIds,
                members: familyMembers
            )
        }
        .onChange(of: radius) { _, _ in
            updateCamera(animated: true)
        }
        .onChange(of: latitude) { _, _ in
            updateCamera(animated: true)
        }
        .onChange(of: longitude) { _, _ in
            updateCamera(animated: true)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button("Annulla") { dismiss() }
                .foregroundStyle(.secondary)

            Spacer()

            Text(isEditing ? "Modifica zona" : "Nuova zona")
                .font(.headline)

            Spacer()

            Button("Salva") { save() }
                .fontWeight(.semibold)
                .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nome")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Es. Scuola", text: $name)
                .textFieldStyle(.plain)
                .padding(14)
                .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!isOwner)
        }
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Emoji")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Self.presetEmojis, id: \.self) { emoji in
                    Button {
                        useCustomEmoji = false
                        selectedPresetEmoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                (!useCustomEmoji && selectedPresetEmoji == emoji)
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOwner)
                }
            }

            Toggle("Emoji personalizzata", isOn: $useCustomEmoji)
                .disabled(!isOwner)

            if useCustomEmoji {
                TextField("Incolla un emoji", text: $customEmoji)
                    .padding(14)
                    .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(!isOwner)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Posizione")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            searchBar

            ZStack(alignment: .top) {
                geofenceMap
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if showSuggestions && !searchVM.suggestions.isEmpty {
                    suggestionsList
                }
            }

            Text("Tieni premuto sulla mappa per spostare il pin")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cerca indirizzo o luogo", text: $searchVM.query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: searchVM.query) { _, new in
                    showSuggestions = searchFocused && !new.trimmingCharacters(in: .whitespaces).isEmpty
                }
                .onChange(of: searchFocused) { _, focused in
                    showSuggestions = focused && !searchVM.query.trimmingCharacters(in: .whitespaces).isEmpty
                }
            if searchVM.isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(12)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!isOwner)
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchVM.suggestions.prefix(5), id: \.self) { result in
                Button {
                    selectSearchResult(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private var geofenceMap: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                Annotation(resolvedEmoji, coordinate: pinCoordinate) {
                    Text(resolvedEmoji)
                        .font(.title)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                MapCircle(center: pinCoordinate, radius: radius)
                    .foregroundStyle(Color.accentColor.opacity(0.18))
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            .mapStyle(.standard)
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        guard isOwner else { return }
                        if case .second(true, let drag?) = value,
                           let coord = proxy.convert(drag.location, from: .local) {
                            latitude = coord.latitude
                            longitude = coord.longitude
                            searchVM.query = ""
                            showSuggestions = false
                            searchFocused = false
                        }
                    }
            )
        }
    }

    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Raggio")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(radius)) m")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            Slider(value: $radius, in: 50...1000, step: 10)
                .disabled(!isOwner)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applica la zona a")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            memberPickerRow(
                summary: memberSummary(allMembers: monitorAllMembers, userIds: monitoredUserIds),
                action: { showMonitorPicker = true }
            )
        }
    }

    private var notifyRecipientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Avvisa")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            memberPickerRow(
                summary: memberSummary(allMembers: notifyAllMembers, userIds: notifyUserIds),
                action: { showNotifyPicker = true }
            )
        }
    }

    private var notifyWhenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quando avvisare")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                Toggle("All'arrivo in zona", isOn: $notifyOnArrive)
                    .padding(.vertical, 10)
                Divider()
                Toggle("All'uscita dalla zona", isOn: $notifyOnLeave)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(!isOwner)

            Text("Esempio: zona Casa, monitora Papà, avvisa te, solo in uscita → «Papà è partito da Casa» quando lascia casa con il telefono e la posizione condivisa attiva.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func memberPickerRow(summary: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isOwner)
    }

    private func memberSummary(allMembers: Bool, userIds: Set<String>) -> String {
        if allMembers { return "Tutti i membri" }
        let names = familyMembers
            .filter { userIds.contains($0.userId) }
            .compactMap { m -> String? in
                let n = m.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return n.isEmpty ? nil : n
            }
        if names.isEmpty { return "Seleziona membri…" }
        return names.joined(separator: ", ")
    }

    // MARK: - Helpers

    private var pinCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func loadExistingIfNeeded() {
        guard let g = existing else { return }
        name = g.name
        radius = g.radius > 0 ? g.radius : 200
        latitude = g.latitude
        longitude = g.longitude
        notifyOnArrive = g.notifyOnArrive
        notifyOnLeave = g.notifyOnLeave

        monitorAllMembers = g.monitoredMemberIds.isEmpty
        monitoredUserIds = Set(g.monitoredMemberIds)
        notifyAllMembers = g.notifyMembers.isEmpty
        notifyUserIds = Set(g.notifyMembers)

        if let e = g.emoji, !e.isEmpty {
            if Self.presetEmojis.contains(e) {
                selectedPresetEmoji = e
                useCustomEmoji = false
            } else {
                customEmoji = e
                useCustomEmoji = true
            }
        }
    }

    private func updateCamera(animated: Bool) {
        let region = mapRegion(center: pinCoordinate, radiusMeters: radius)
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    private func mapRegion(center: CLLocationCoordinate2D, radiusMeters: Double) -> MKCoordinateRegion {
        let metersPerDegree = 111_000.0
        let delta = max((radiusMeters * 2.8) / metersPerDegree, 0.004)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
        )
    }

    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        showSuggestions = false
        searchFocused = false
        searchVM.query = searchVM.fullText(of: result)

        Task {
            await searchVM.resolveCoordinate(from: result) { coord in
                latitude = coord.latitude
                longitude = coord.longitude
                updateCamera(animated: true)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = Auth.auth().currentUser?.uid ?? ""

        Task {
            defer { isSaving = false }
            do {
                let geofence: KBGeofence
                if let existing {
                    geofence = existing
                    geofence.name = trimmedName
                    geofence.emoji = resolvedEmoji
                    geofence.latitude = latitude
                    geofence.longitude = longitude
                    geofence.radius = radius
                    geofence.notifyOnArrive = notifyOnArrive
                    geofence.notifyOnLeave = notifyOnLeave
                    geofence.monitoredMemberIds = monitorAllMembers ? [] : Array(monitoredUserIds).sorted()
                    geofence.notifyMembers = notifyAllMembers ? [] : Array(notifyUserIds).sorted()
                    geofence.updatedAt = Date()
                } else {
                    geofence = KBGeofence(
                        familyId: familyId,
                        name: trimmedName,
                        emoji: resolvedEmoji,
                        latitude: latitude,
                        longitude: longitude,
                        radius: radius,
                        notifyOnArrive: notifyOnArrive,
                        notifyOnLeave: notifyOnLeave,
                        notifyMembers: notifyAllMembers ? [] : Array(notifyUserIds).sorted(),
                        monitoredMemberIds: monitorAllMembers ? [] : Array(monitoredUserIds).sorted(),
                        createdBy: uid
                    )
                    modelContext.insert(geofence)
                }

                try modelContext.save()
                try await remote.upsert(geofence)
                dismiss()
            } catch {
                KBLog.sync.kbError("GeofenceEditView save failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Address search

@MainActor
final class GeofenceAddressSearchVM: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var query: String = "" {
        didSet { updateCompleter() }
    }
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    private func updateCompleter() {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            suggestions = []
            isSearching = false
            completer.cancel()
        } else {
            isSearching = true
            completer.queryFragment = q
        }
    }

    func fullText(of result: MKLocalSearchCompletion) -> String {
        if result.subtitle.isEmpty { return result.title }
        return "\(result.title), \(result.subtitle)"
    }

    func resolveCoordinate(
        from completion: MKLocalSearchCompletion,
        onResolved: @escaping (CLLocationCoordinate2D) -> Void
    ) async {
        let request = MKLocalSearch.Request(completion: completion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coord = response.mapItems.first?.placemark.coordinate,
                  CLLocationCoordinate2DIsValid(coord) else { return }
            onResolved(coord)
        } catch {
            KBLog.app.kbError("GeofenceEditView search resolve failed: \(error.localizedDescription)")
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            suggestions = completer.results
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            suggestions = []
            isSearching = false
        }
    }
}
