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
    
    private var activeMembersCount: Int {
        guard !activeFamilyId.isEmpty else { return 0 }
        return members.filter { $0.familyId == activeFamilyId && !$0.isDeleted }.count
    }
    
    private var showInvite: Bool { hasFamily && activeMembersCount < 2 }
    
    private var heroPhotoURL: URL? {
        guard let s = activeFamily?.heroPhotoURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    
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
                    if hasFamily { showHeroPicker = true }
                    else { coordinator.navigate(to: .familySettings) }
                }
                
                // GRID
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    HomeCardView(title: "To-Do", subtitle: "Lista condivisa", systemImage: "checklist") { go(.todo) }
                    HomeCardView(title: "Calendario", subtitle: "Eventi e affidamenti", systemImage: "calendar") { go(.calendar) }
                    
                    HomeCardView(title: "Cure", subtitle: "Promemoria e fatto/non fatto", systemImage: "cross.case") {
                        KBLog.navigation.debug("Tap Cure")
                        // go(.care)
                    }
                    
                    HomeCardView(title: "Chat", subtitle: "Messaggi famiglia", systemImage: "message") {
                        KBLog.navigation.debug("Tap Chat")
                        // go(.chat)
                    }
                    
                    HomeCardView(title: "Documenti", subtitle: "Carte importanti", systemImage: "doc.text") {
                        KBLog.navigation.debug("Tap Documenti")
                        go(.document)
                    }
                    
                    HomeCardView(title: "Spese", subtitle: "Rette, visite, extra", systemImage: "eurosign.circle") {
                        KBLog.navigation.debug("Tap Spese")
                        // go(.expenses)
                    }
                    
                    HomeCardView(title: "Timeline", subtitle: "Storia e tappe", systemImage: "clock.arrow.circlepath") {
                        KBLog.navigation.debug("Tap Timeline")
                        // go(.timeline)
                    }
                    
                    HomeCardView(title: "Family", subtitle: "Membri e inviti", systemImage: "person.2.fill") {
                        coordinator.navigate(to: .familySettings)
                    }
                }
                
                if showInvite {
                    InviteCardView { coordinator.navigate(to: .inviteCode) }
                }
            }
            .padding()
        }
        .navigationTitle("KidBox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { coordinator.navigate(to: .profile) } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profilo")
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button { coordinator.navigate(to: .settings) } label: {
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
            Task { await prepareHeroCrop(item: newItem) }
        }
        
        // ✅ Cropper sheet (estratto in subview per evitare type-check lento)
        .sheet(isPresented: $showHeroCropper) {
            HeroCropperSheet(
                data: pendingHeroImageData,
                initialCrop: initialCrop,
                isUploading: isUploadingHero,
                onCancel: {
                    // chiudi solo il cropper
                    showHeroCropper = false
                    pendingHeroImageData = nil
                    pickedHeroItem = nil
                },
                onSave: { crop in
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
    
    @MainActor
    private func prepareHeroCrop(item: PhotosPickerItem) async {
        heroUploadError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                pickedHeroItem = nil
                return
            }
            pendingHeroImageData = data
            showHeroCropper = true
        } catch {
            heroUploadError = error.localizedDescription
            pickedHeroItem = nil
        }
    }
    
    // MARK: - Step 2: upload + save crop
    
    @MainActor
    private func uploadHeroWithCrop(crop: HeroCrop) async {
        guard let familyId = activeFamily?.id, !familyId.isEmpty else { return }
        guard let data = pendingHeroImageData else { return }
        guard !isUploadingHero else { return }
        
        isUploadingHero = true
        heroUploadError = nil
        defer { isUploadingHero = false }
        
        do {
            
            _ = try await heroService.setHeroPhoto(
                familyId: familyId,
                imageData: data,
                crop: crop
            )
            
            // chiudi sheet + reset selection
            pendingHeroImageData = nil
            pickedHeroItem = nil
            showHeroCropper = false
            
            // niente altro: il realtime listener su KBFamily aggiorna la home
        } catch {
            heroUploadError = error.localizedDescription
        }
    }
    
    // MARK: - Navigation
    
    private func go(_ routeIfFamily: Route, else routeIfNoFamily: Route = .familySettings) {
        coordinator.navigate(to: hasFamily ? routeIfFamily : routeIfNoFamily)
    }
}

// MARK: - Subview sheet (riduce errori type-check)

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
