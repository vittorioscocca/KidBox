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
import Combine

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
    
    @Query(sort: \KBUserProfile.updatedAt, order: .reverse) private var profiles: [KBUserProfile]
    
    private var myProfile: KBUserProfile? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return profiles.first(where: { $0.uid == uid })
    }
    
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
                
                // ✅ Grid estratta in subview per evitare type-check timeout
                HomeCardGrid(hasFamily: hasFamily, familyId: activeFamilyId) { destination in
                    navigate(to: destination)
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
                    coordinator.navigate(to: .profile)
                } label: {
                    ProfileAvatarView(avatarData: myProfile?.avatarData)
                        .frame(width: 34, height: 34)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .onAppear {
            guard !activeFamilyId.isEmpty else { return }
            BadgeManager.shared.startListening(familyId: activeFamilyId)
        }
        // ✅ Picker
        .photosPicker(isPresented: $showHeroPicker, selection: $pickedHeroItem, matching: .images)
        .onChange(of: pickedHeroItem) { _, newItem in
            guard let newItem else { return }
            guard !isUploadingHero else { return }
            KBLog.sync.debug("Home: hero picker item selected -> prepare crop")
            Task { await prepareHeroCrop(item: newItem) }
        }
        
        // ✅ Cropper sheet
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
    
    struct ProfileAvatarView: View {
        let avatarData: Data?
        
        var body: some View {
            Group {
                if let avatarData, let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(.quaternary, lineWidth: 1))
        }
    }
    
    // MARK: - Navigation
    
    /// Centralized navigation helper. Routes non-members to Family settings.
    private func navigate(to destination: HomeDestination) {
        switch destination {
        case .familySettings:
            KBLog.navigation.debug("Home: navigate -> familySettings")
            coordinator.navigate(to: .familySettings)
        case .profile:
            KBLog.navigation.debug("Home: navigate -> profile")
            coordinator.navigate(to: .profile)
        case .settings:
            KBLog.navigation.debug("Home: navigate -> settings")
            coordinator.navigate(to: .settings)
        case .inviteCode:
            KBLog.navigation.debug("Home: navigate -> inviteCode")
            coordinator.navigate(to: .inviteCode)
        default:
            if hasFamily {
                KBLog.navigation.debug("Home: navigate -> \(String(describing: destination), privacy: .public)")
                coordinator.navigate(to: destination.route)
            } else {
                KBLog.navigation.debug("Home: navigation blocked (no family) -> FamilySettings")
                coordinator.navigate(to: .familySettings)
            }
        }
    }
    
    // MARK: - Step 1: read bytes then open cropper
    
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
            let urlString = try await heroService.setHeroPhoto(
                familyId: familyId,
                imageData: data,
                crop: crop
            )
            
            if let family = activeFamily {
                family.heroPhotoURL = urlString
                family.heroPhotoUpdatedAt = Date()
                family.heroPhotoScale = crop.scale
                family.heroPhotoOffsetX = crop.offsetX
                family.heroPhotoOffsetY = crop.offsetY
                do {
                    try modelContext.save()
                    KBLog.sync.info("Home: hero local update saved familyId=\(familyId, privacy: .public)")
                } catch {
                    KBLog.sync.error("Home: hero local update failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            pendingHeroImageData = nil
            pickedHeroItem = nil
            showHeroCropper = false
            KBLog.sync.info("Home: hero upload OK familyId=\(familyId, privacy: .public)")
            
        } catch {
            heroUploadError = error.localizedDescription
            KBLog.sync.error("Home: hero upload FAILED familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - HomeDestination

enum HomeDestination {
    case notes, todo, calendar, care
    case chat, document, expenses, timeline
    case familyLocation(familyId: String), familyPhotos, familySettings
    case askExpert, profile, settings, inviteCode
    
    /// Mappa verso il Route dell'AppCoordinator.
    var route: Route {
        switch self {
        case .notes:                         return .calendar
        case .todo:                          return .todo
        case .calendar:                      return .calendar
        case .care:                          return .calendar
        case .chat:                          return .chat
        case .document:                      return .document
        case .expenses:                      return .calendar
        case .timeline:                      return .calendar
        case .familyLocation(let familyID):  return .familyLocation(familyId: familyID)
        case .familyPhotos:                  return .calendar
        case .familySettings:                return .familySettings
        case .askExpert:                     return .calendar
        case .profile:                       return .profile
        case .settings:                      return .settings
        case .inviteCode:                    return .inviteCode
        }
    }
}

// MARK: - LocationSharingObserver
// ObservableObject leggero che legge lo stato di sharing da UserDefaults.
// Si aggiorna quando l'app torna in foreground (scenePhase) o riceve
// la notifica kbProfileDisplayNameUpdated (riutilizzata come trigger generico).

final class LocationSharingObserver: ObservableObject {
    @Published private(set) var isSharing: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        refresh()
        
        // Aggiorna quando l'app torna in foreground
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        
        // Aggiorna quando il ViewModel cambia lo stato di sharing
        NotificationCenter.default.publisher(for: .kbLocationSharingStateChanged)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }
    
    func refresh() {
        isSharing = UserDefaults.standard.bool(forKey: KBLocationDefaults.isSharing)
    }
}

// MARK: - HomeCardGrid

private struct HomeCardGrid: View {
    let hasFamily: Bool
    let familyId: String
    let onNavigate: (HomeDestination) -> Void
    
    @ObservedObject private var badge = BadgeManager.shared
    @StateObject private var locationObserver = LocationSharingObserver()
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            cardNote
            cardTodo
            cardCalendar
            cardCure
            cardChat
            cardDocumenti
            cardSpese
            cardTimeline
            cardPosizione
            cardFoto
            cardFamily
            cardEsperto
        }
    }
    
    // MARK: Cards
    
    private var cardNote: some View {
        HomeCardView(title: "Note", subtitle: "Appunti veloci", systemImage: "note.text", tint: .yellow) {
            KBLog.navigation.debug("Home: tap Notes")
        }
    }
    
    private var cardTodo: some View {
        HomeCardView(title: "To-Do", subtitle: "Lista condivisa", systemImage: "checklist", tint: .blue) {
            KBLog.navigation.debug("Home: tap Todo")
            onNavigate(.todo)
        }
    }
    
    private var cardCalendar: some View {
        HomeCardView(title: "Calendario", subtitle: "Eventi e affidamenti", systemImage: "calendar", tint: .purple) {
            KBLog.navigation.debug("Home: tap Calendar")
            onNavigate(.calendar)
        }
    }
    
    private var cardCure: some View {
        HomeCardView(title: "Cure", subtitle: "Promemoria e fatto/non fatto", systemImage: "cross.case", tint: .red) {
            KBLog.navigation.debug("Home: tap Care")
        }
    }
    
    private var cardChat: some View {
        ZStack(alignment: .topTrailing) {
            HomeCardView(title: "Chat", subtitle: "Messaggi famiglia", systemImage: "message.fill", tint: .green) {
                KBLog.navigation.debug("Home: tap Chat")
                onNavigate(.chat)
            }
            if badge.chat > 0 {
                BadgeView(count: badge.chat)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
    }
    
    private var cardDocumenti: some View {
        ZStack(alignment: .topTrailing) {
            HomeCardView(title: "Documenti", subtitle: "Carte importanti", systemImage: "doc.text", tint: .orange) {
                KBLog.navigation.debug("Home: tap Documents")
                onNavigate(.document)
            }
            if badge.documents > 0 {
                BadgeView(count: badge.documents)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
    }
    
    private var cardSpese: some View {
        HomeCardView(title: "Spese", subtitle: "Rette, visite, extra", systemImage: "eurosign.circle", tint: .mint) {
            KBLog.navigation.debug("Home: tap Expenses")
        }
    }
    
    private var cardTimeline: some View {
        HomeCardView(title: "Timeline", subtitle: "Storia e tappe", systemImage: "clock.arrow.circlepath", tint: .indigo) {
            KBLog.navigation.debug("Home: tap Timeline")
        }
    }
    
    // Posizione famiglia — con indicatore pulsante se condivisione attiva
    private var cardPosizione: some View {
        ZStack(alignment: .topTrailing) {
            HomeCardView(title: "Posizione", subtitle: "Dove sono tutti", systemImage: "location.fill", tint: .cyan) {
                KBLog.navigation.debug("Home: tap FamilyLocation")
                onNavigate(.familyLocation(familyId: familyId))
            }
            
            if locationObserver.isSharing {
                LocationSharingPulse()
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
    }
    
    private var cardFoto: some View {
        HomeCardView(title: "Foto", subtitle: "Album condiviso", systemImage: "photo.stack.fill", tint: .pink) {
            KBLog.navigation.debug("Home: tap FamilyPhotos")
            onNavigate(.familyPhotos)
        }
    }
    
    private var cardFamily: some View {
        HomeCardView(title: "Family", subtitle: "Membri e inviti", systemImage: "person.2.fill", tint: .teal) {
            KBLog.navigation.debug("Home: tap FamilySettings")
            onNavigate(.familySettings)
        }
    }
    
    private var cardEsperto: some View {
        HomeCardView(title: "Chiedi all'Esperto", subtitle: "Consigli su famiglia e figli", systemImage: "brain.head.profile", tint: .purple) {
            KBLog.navigation.debug("Home: tap AskExpert")
            onNavigate(.askExpert)
        }
    }
}

// MARK: - LocationSharingPulse
// Punto verde con animazione pulse, identico al badge rosso ma verde e pulsante.

private struct LocationSharingPulse: View {
    @State private var pulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 28, height: 28)
                .scaleEffect(pulsing ? 2.2 : 1.0)
                .opacity(pulsing ? 0 : 0.7)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: pulsing
                )
            
            Circle()
                .fill(Color.green.opacity(0.35))
                .frame(width: 20, height: 20)
                .scaleEffect(pulsing ? 1.8 : 1.0)
                .opacity(pulsing ? 0 : 0.8)
                .animation(
                    .easeOut(duration: 1.4).delay(0.4).repeatForever(autoreverses: false),
                    value: pulsing
                )
            
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .green.opacity(0.6), radius: 4, x: 0, y: 0)
        }
        // .task viene chiamato ogni volta che la view appare,
        // incluso il ritorno dalla navigation — a differenza di .onAppear
        .task {
            // Reset necessario: se la view era già apparsa con pulsing=true
            // e viene ri-mostrata, SwiftUI non la ricrea ma .task riparte.
            // Resettando a false forziamo il ricalcolo dell'animazione.
            pulsing = false
            // Piccolo delay per permettere a SwiftUI di registrare il reset
            try? await Task.sleep(for: .milliseconds(50))
            pulsing = true
        }
    }
}

// MARK: - BadgeView

private struct BadgeView: View {
    let count: Int
    
    var body: some View {
        let text = count > 99 ? "99+" : "\(count)"
        let isCircle = count < 10
        
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, isCircle ? 0 : 7)
            .frame(width: isCircle ? 18 : nil, height: 18)
            .background(
                Group {
                    if isCircle {
                        Circle().fill(Color.red)
                    } else {
                        Capsule().fill(Color.red)
                    }
                }
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
    }
}

// MARK: - HeroCropperSheet

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
