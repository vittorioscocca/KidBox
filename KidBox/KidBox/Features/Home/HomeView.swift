//
//  HomeView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import FirebaseAuth
import OSLog
import SwiftData
import PhotosUI

/// Home screen entry point.
///
/// Responsibilities:
/// - Shows the family "hero" card (photo + crop metadata)
/// - Provides quick navigation cards to app sections
/// - Handles hero photo picking + crop flow (picker -> cropper -> upload)
///
/// Logging policy:
/// - ✅ Log only user-driven actions (taps, start/end of flows, failures).
/// - ❌ Avoid logs inside `body` evaluation paths that may spam due to SwiftUI re-rendering.
/// - ✅ Keep logs short and privacy-safe.
struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    // Picker + cropper
    @State private var showHeroPicker = false
    @State private var pickedHeroItem: PhotosPickerItem?
    @State private var pendingHeroImageData: Data?
    @State private var showHeroCropper = false
    
    @State private var isUploadingHero = false
    @State private var heroUploadError: String?
    
    private let heroService = FamilyHeroPhotoService()
    
    private var activeFamily: KBFamily? { families.first }
    private var hasFamily: Bool { activeFamily != nil }
    private var activeFamilyId: String { activeFamily?.id ?? "" }
    
    /// Members count for the active family (excludes soft-deleted members).
    private var activeMembersCount: Int {
        guard !activeFamilyId.isEmpty else { return 0 }
        return members.filter { $0.familyId == activeFamilyId && !$0.isDeleted }.count
    }
    
    /// Suggest invitation when user is in a family but seems alone.
    private var showInvite: Bool { hasFamily && activeMembersCount < 2 }
    
    private var heroPhotoURL: URL? {
        guard let s = activeFamily?.heroPhotoURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    
    /// Initial crop values for the cropper UI (persisted on KBFamily).
    private var initialCrop: HeroCrop {
        HeroCrop(
            scale: activeFamily?.heroPhotoScale ?? 1.0,
            offsetX: activeFamily?.heroPhotoOffsetX ?? 0.0,
            offsetY: activeFamily?.heroPhotoOffsetY ?? 0.0
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                
                // HERO
                HomeHeroCard(
                    title: hasFamily ? (activeFamily?.name ?? "La tua famiglia") : "Benvenuto 👋",
                    subtitle: hasFamily ? "" : "Crea o unisciti a una famiglia per iniziare.",
                    dateText: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    rightBadgeText: hasFamily ? "\(activeMembersCount) membri" : "",
                    photoURL: heroPhotoURL,
                    photoUpdatedAt: activeFamily?.heroPhotoUpdatedAt,
                    scale: activeFamily?.heroPhotoScale ?? 1.0,
                    offsetX: activeFamily?.heroPhotoOffsetX ?? 0.0,
                    offsetY: activeFamily?.heroPhotoOffsetY ?? 0.0,
                    isBusy: isUploadingHero
                ) {
                    if hasFamily {
                        KBLog.navigation.debug("Home: tap hero -> open picker familyId=\(activeFamilyId, privacy: .public)")
                        showHeroPicker = true
                    } else {
                        KBLog.navigation.debug("Home: tap hero without family -> go FamilySettings")
                        coordinator.navigate(to: .familySettings)
                    }
                }
                .id(activeFamily?.heroPhotoUpdatedAt ?? activeFamily?.updatedAt)
                
                // GRID
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    HomeCardView(title: "Note", subtitle: "Appunti veloci", systemImage: "note.text", tint: .yellow) {
                        KBLog.navigation.debug("Home: tap Notes")
                        // go(.notes)
                    }
                    
                    HomeCardView(title: "To-Do", subtitle: "Lista condivisa", systemImage: "checklist", tint: .blue) {
                        KBLog.navigation.debug("Home: tap Todo")
                        go(.todo)
                    }
                    
                    HomeCardView(title: "Calendario", subtitle: "Eventi e affidamenti", systemImage: "calendar", tint: .purple) {
                        KBLog.navigation.debug("Home: tap Calendar")
                        go(.calendar)
                    }
                    
                    HomeCardView(title: "Cure", subtitle: "Promemoria e fatto/non fatto", systemImage: "cross.case", tint: .red) {
                        KBLog.navigation.debug("Home: tap Care")
                        // go(.care)
                    }
                    
                    HomeCardView(title: "Chat", subtitle: "Messaggi famiglia", systemImage: "message", tint: .green) {
                        KBLog.navigation.debug("Home: tap Chat")
                        // go(.chat)
                    }
                    
                    HomeCardView(title: "Documenti", subtitle: "Carte importanti", systemImage: "doc.text", tint: .orange) {
                        KBLog.navigation.debug("Home: tap Documents")
                        go(.document)
                    }
                    
                    HomeCardView(title: "Spese", subtitle: "Rette, visite, extra", systemImage: "eurosign.circle", tint: .mint) {
                        KBLog.navigation.debug("Home: tap Expenses")
                        // go(.expenses)
                    }
                    
                    HomeCardView(title: "Timeline", subtitle: "Storia e tappe", systemImage: "clock.arrow.circlepath", tint: .indigo) {
                        KBLog.navigation.debug("Home: tap Timeline")
                        // go(.timeline)
                    }
                    
                    HomeCardView(title: "Family", subtitle: "Membri e inviti", systemImage: "person.2.fill", tint: .teal) {
                        KBLog.navigation.debug("Home: tap FamilySettings")
                        coordinator.navigate(to: .familySettings)
                    }
                }
                
                if showInvite {
                    InviteCardView {
                        KBLog.navigation.debug("Home: tap InviteCard -> inviteCode")
                        coordinator.navigate(to: .inviteCode)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("KidBox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    KBLog.navigation.debug("Home: tap Profile")
                    coordinator.navigate(to: .profile)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profilo")
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    KBLog.navigation.debug("Home: tap Settings")
                    coordinator.navigate(to: .settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Impostazioni")
            }
        }
        
        // ✅ Picker
        .photosPicker(isPresented: $showHeroPicker, selection: $pickedHeroItem, matching: .images)
        .onChange(of: pickedHeroItem) { _, newItem in
            guard let newItem else { return }
            guard !isUploadingHero else { return }
            KBLog.sync.debug("Home: hero picker item selected -> prepare crop")
            Task { await prepareHeroCrop(item: newItem) }
        }
        
        // ✅ Cropper sheet (estratto in subview per evitare type-check lento)
        .sheet(isPresented: $showHeroCropper) {
            HeroCropperSheet(
                data: pendingHeroImageData,
                initialCrop: initialCrop,
                isUploading: isUploadingHero,
                onCancel: {
                    KBLog.sync.debug("Home: hero crop canceled")
                    showHeroCropper = false
                    pendingHeroImageData = nil
                    pickedHeroItem = nil
                },
                onSave: { crop in
                    KBLog.sync.debug("Home: hero crop save tapped -> upload")
                    Task { await uploadHeroWithCrop(crop: crop) }
                }
            )
        }
        
        // ✅ Error alert
        .alert(
            "Immagine non aggiornata",
            isPresented: Binding(
                get: { heroUploadError != nil },
                set: { if !$0 { heroUploadError = nil } }
            )
        ) {
            Button("OK") { heroUploadError = nil }
        } message: {
            Text(heroUploadError ?? "")
        }
    }
    
    // MARK: - Step 1: read bytes then open cropper
    
    /// Loads selected photo bytes into memory and opens the cropper sheet.
    ///
    /// - Note: We keep the original selected bytes and apply crop metadata separately.
    @MainActor
    private func prepareHeroCrop(item: PhotosPickerItem) async {
        heroUploadError = nil
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                KBLog.sync.error("Home: hero picker loadTransferable returned nil")
                pickedHeroItem = nil
                return
            }
            
            pendingHeroImageData = data
            showHeroCropper = true
            KBLog.sync.info("Home: hero bytes loaded -> cropper opened (bytes=\(data.count, privacy: .public))")
            
        } catch {
            heroUploadError = error.localizedDescription
            pickedHeroItem = nil
            KBLog.sync.error("Home: hero bytes load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Step 2: upload + save crop
    
    /// Uploads the hero photo and persists crop metadata (scale/offset) on the family document.
    ///
    /// Expected behavior:
    /// - On success: close cropper, reset picker state.
    /// - No explicit local update needed: the family realtime listener updates KBFamily.
    @MainActor
    private func uploadHeroWithCrop(crop: HeroCrop) async {
        guard let familyId = activeFamily?.id, !familyId.isEmpty else {
            KBLog.sync.error("Home: uploadHeroWithCrop aborted (no familyId)")
            return
        }
        guard let data = pendingHeroImageData else {
            KBLog.sync.error("Home: uploadHeroWithCrop aborted (no pending image data)")
            return
        }
        guard !isUploadingHero else { return }
        
        isUploadingHero = true
        heroUploadError = nil
        KBLog.sync.info("Home: hero upload started familyId=\(familyId, privacy: .public) bytes=\(data.count, privacy: .public)")
        defer {
            isUploadingHero = false
            KBLog.sync.debug("Home: hero upload finished (busy=false)")
        }
        
        do {
            _ = try await heroService.setHeroPhoto(
                familyId: familyId,
                imageData: data,
                crop: crop
            )
            
            pendingHeroImageData = nil
            pickedHeroItem = nil
            showHeroCropper = false
            
            KBLog.sync.info("Home: hero upload OK familyId=\(familyId, privacy: .public)")
            // Listener realtime aggiorna la home.
            
        } catch {
            heroUploadError = error.localizedDescription
            KBLog.sync.error("Home: hero upload FAILED familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Navigation
    
    /// Centralized navigation helper that routes non-members to Family settings.
    private func go(_ routeIfFamily: Route, else routeIfNoFamily: Route = .familySettings) {
        if hasFamily {
            coordinator.navigate(to: routeIfFamily)
        } else {
            KBLog.navigation.debug("Home: navigation blocked (no family) -> FamilySettings")
            coordinator.navigate(to: routeIfNoFamily)
        }
    }
}

// MARK: - Subview sheet (riduce errori type-check)

/// A small wrapper sheet that shows the cropper if bytes are available.
private struct HeroCropperSheet: View {
    let data: Data?
    let initialCrop: HeroCrop
    let isUploading: Bool
    let onCancel: () -> Void
    let onSave: (HeroCrop) -> Void
    
    var body: some View {
        if let data {
            HeroPhotoCropperView(
                imageData: data,
                initialCrop: initialCrop,
                isSaving: isUploading,
                onCancel: onCancel,
                onSave: onSave
            )
        } else {
            VStack(spacing: 12) {
                Text("Nessuna immagine")
                Button("Chiudi") { onCancel() }
            }
            .padding()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppCoordinator())
    }
    .modelContainer(ModelContainerProvider.makeContainer(inMemory: true))
}
