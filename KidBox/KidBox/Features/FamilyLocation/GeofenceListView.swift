//
//  GeofenceListView.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore

/// Elenco zone di arrivo/partenza della famiglia.
struct GeofenceListView: View {

    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = KBSubscriptionManager.shared

    @Query private var geofences: [KBGeofence]

    @State private var showAddSheet = false
    @State private var geofenceToEdit: KBGeofence?
    @State private var isSavingToggle = false
    @State private var geofenceListener: ListenerRegistration?

    private let remote = GeofenceRemoteStore()

    private var isOwner: Bool { subscriptionManager.isFamilyOwner }

    private var sortedGeofences: [KBGeofence] {
        geofences.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.18)
            : Color(.systemBackground)
    }

    private var accent: Color { Color.accentColor }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _geofences = Query(
            filter: #Predicate<KBGeofence> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBGeofence.name, order: .forward)]
        )
    }

    var body: some View {
        Group {
            if sortedGeofences.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sortedGeofences, id: \.id) { geofence in
                        geofenceRow(geofence)
                            .listRowBackground(cardBackground)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if isOwner {
                                    Button(role: .destructive) {
                                        deleteGeofence(geofence)
                                    } label: {
                                        Label("Elimina", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Zone di arrivo")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .tint(accent)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            GeofenceEditView(familyId: familyId, existing: nil, isOwner: true)
        }
        .sheet(item: $geofenceToEdit) { geofence in
            GeofenceEditView(familyId: familyId, existing: geofence, isOwner: isOwner)
        }
        .onAppear {
            startRealtimeSync()
        }
        .onDisappear {
            geofenceListener?.remove()
            geofenceListener = nil
        }
    }

    // MARK: - Rows

    private func geofenceRow(_ geofence: KBGeofence) -> some View {
        HStack(spacing: 14) {
            Text(displayEmoji(for: geofence))
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(geofence.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(Int(geofence.radius > 0 ? geofence.radius : 200)) m")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            statusBadge(isActive: geofence.isActive)

            Toggle("", isOn: activeBinding(for: geofence))
                .labelsHidden()
                .disabled(isSavingToggle)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isOwner else { return }
            geofenceToEdit = geofence
        }
    }

    private func displayEmoji(for geofence: KBGeofence) -> String {
        let e = geofence.emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return e.isEmpty ? "📍" : e
    }

    private func statusBadge(isActive: Bool) -> some View {
        Text(isActive ? "Attiva" : "Inattiva")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isActive ? Color.green : Color.secondary).opacity(0.14),
                in: Capsule()
            )
    }

    private func activeBinding(for geofence: KBGeofence) -> Binding<Bool> {
        Binding(
            get: { geofence.isActive },
            set: { newValue in
                toggleActive(geofence, isActive: newValue)
            }
        )
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 48))
                .foregroundStyle(accent)
            Text("Nessuna zona configurata")
                .font(.headline)
                .foregroundStyle(.primary)
            if isOwner {
                Button {
                    showAddSheet = true
                } label: {
                    Text("Aggiungi zona")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func toggleActive(_ geofence: KBGeofence, isActive: Bool) {
        guard geofence.isActive != isActive else { return }
        geofence.isActive = isActive
        geofence.updatedAt = Date()
        isSavingToggle = true

        Task {
            defer { isSavingToggle = false }
            do {
                try modelContext.save()
                try await remote.upsert(geofence)
            } catch {
                geofence.isActive = !isActive
                try? modelContext.save()
                KBLog.sync.kbError("GeofenceListView toggle failed: \(error.localizedDescription)")
            }
        }
    }

    private func deleteGeofence(_ geofence: KBGeofence) {
        let id = geofence.id
        Task {
            do {
                try await remote.delete(id: id, familyId: familyId)
                modelContext.delete(geofence)
                try modelContext.save()
            } catch {
                KBLog.sync.kbError("GeofenceListView delete failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Realtime sync

    private func startRealtimeSync() {
        geofenceListener?.remove()
        geofenceListener = remote.listen(
            familyId: familyId,
            onChange: { changes in
                Task { @MainActor in
                    applyInbound(changes)
                }
            },
            onError: { error in
                KBLog.sync.kbError("GeofenceListView listener: \(error.localizedDescription)")
            }
        )
    }

    @MainActor
    private func applyInbound(_ changes: [GeofenceRemoteChange]) {
        for change in changes {
            switch change {
            case .upsert(let dto):
                applyDTO(dto)
            case .remove(let id):
                let gid = id
                let desc = FetchDescriptor<KBGeofence>(predicate: #Predicate { $0.id == gid })
                if let row = try? modelContext.fetch(desc).first {
                    modelContext.delete(row)
                }
            }
        }
        try? modelContext.save()
    }

    @MainActor
    private func applyDTO(_ dto: GeofenceRemoteDTO) {
        if dto.isDeleted {
            let gid = dto.id
            let desc = FetchDescriptor<KBGeofence>(predicate: #Predicate { $0.id == gid })
            if let row = try? modelContext.fetch(desc).first {
                modelContext.delete(row)
            }
            return
        }

        let gid = dto.id
        let desc = FetchDescriptor<KBGeofence>(predicate: #Predicate { $0.id == gid })
        let remoteTs = dto.updatedAt ?? Date.distantPast

        if let existing = try? modelContext.fetch(desc).first {
            guard remoteTs >= existing.updatedAt else { return }
            existing.name = dto.name
            existing.emoji = dto.emoji
            existing.latitude = dto.latitude
            existing.longitude = dto.longitude
            existing.radius = dto.radius
            existing.notifyOnArrive = dto.notifyOnArrive
            existing.notifyOnLeave = dto.notifyOnLeave
            existing.notifyMembers = dto.notifyMembers
            existing.monitoredMemberIds = dto.monitoredMemberIds
            existing.isActive = dto.isActive
            existing.isDeleted = false
            existing.updatedAt = remoteTs
            if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
        } else {
            let row = KBGeofence(
                id: dto.id,
                familyId: dto.familyId,
                name: dto.name,
                emoji: dto.emoji,
                latitude: dto.latitude,
                longitude: dto.longitude,
                radius: dto.radius,
                notifyOnArrive: dto.notifyOnArrive,
                notifyOnLeave: dto.notifyOnLeave,
                notifyMembers: dto.notifyMembers,
                monitoredMemberIds: dto.monitoredMemberIds,
                isActive: dto.isActive,
                createdBy: dto.createdBy ?? "",
                createdAt: dto.createdAt ?? Date(),
                updatedAt: remoteTs,
                isDeleted: false
            )
            modelContext.insert(row)
        }
    }
}
