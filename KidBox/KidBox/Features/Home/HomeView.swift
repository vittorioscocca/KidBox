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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Dynamic theme (same as LoginView)
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
    
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    // Picker + cropper
    @State private var showHeroPicker = false
    @State private var pickedHeroItem: PhotosPickerItem?
    @State private var pendingHeroImageData: Data?
    @State private var showHeroCropper = false
    
    @State private var isUploadingHero = false
    @State private var heroUploadError: String?
    
    // MARK: - FAB
    @State private var fabExpanded = false
    @State private var showFamilySwitcher = false
    
    @Query(sort: \KBUserProfile.updatedAt, order: .reverse) private var profiles: [KBUserProfile]
    
    private var myProfile: KBUserProfile? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return profiles.first(where: { $0.uid == uid })
    }
    
    private let heroService = FamilyHeroPhotoService()
    
    private var activeFamily: KBFamily? {
        ActiveFamilyResolver.family(from: families, activeFamilyId: coordinator.activeFamilyId)
    }
    private var hasFamily: Bool { activeFamily != nil }
    private var activeFamilyId: String { activeFamily?.id ?? "" }
    
    /// `@Query` può essere vuota un attimo dopo il login; `AvatarRemoteStore` senza `familyId`
    /// non prova il path famiglia dopo un 404 su `users/.../avatar.jpg`.
    private var effectiveFamilyIdForAvatar: String {
        if !activeFamilyId.isEmpty { return activeFamilyId }
        let g = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId") ?? ""
        if !g.isEmpty { return g }
        if let c = coordinator.activeFamilyId, !c.isEmpty { return c }
        return ""
    }
    
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
    private let avatarRemoteStore = AvatarRemoteStore()
    
    /// Initial crop values for the cropper UI (persisted on KBFamily).
    private var initialCrop: HeroCrop {
        HeroCrop(
            scale: activeFamily?.heroPhotoScale ?? 1.0,
            offsetX: activeFamily?.heroPhotoOffsetX ?? 0.0,
            offsetY: activeFamily?.heroPhotoOffsetY ?? 0.0
        )
    }

    /// Allineato ad Android Home: titolo KidBox + nome famiglia a sinistra, switch a destra (centrato verticalmente).
    private var homeTitleHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KidBox")
                    .font(.system(size: 34, weight: .heavy))
                    .kerning(-0.5)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.primary)
                if hasFamily, let familyName = activeFamily?.name, !familyName.isEmpty {
                    Text(familyName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if hasFamily {
                Button {
                    showFamilySwitcher = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : Color.primary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cambia famiglia")
            }
        }
        .padding(.top, 4)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            if fabExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            fabExpanded = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            ScrollView {
                VStack(spacing: 14) {
                    homeTitleHeader
                    
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
                            KBLog.navigation.kbDebug("Home: tap hero -> open picker familyId=\(activeFamilyId)")
                            showHeroPicker = true
                        } else {
                            KBLog.navigation.kbDebug("Home: tap hero without family -> go FamilySettings")
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
                            KBLog.navigation.kbDebug("Home: tap InviteCard -> inviteCode")
                            coordinator.navigate(to: .inviteCode)
                        }
                    }
                }
                .padding()
            }
        } // ZStack
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if hasFamily {
                HomeFAB(familyId: activeFamilyId, isExpanded: $fabExpanded)
                    .padding(.trailing, 20)
                    .padding(.bottom, 32)
                    .zIndex(2)
            }
        }
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
                    KBLog.navigation.kbDebug("Home: tap Settings")
                    coordinator.navigate(to: .settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Impostazioni")
            }
        }
        .sheet(isPresented: $showFamilySwitcher) {
            FamilySwitcherView()
                .environmentObject(coordinator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            KBLog.sync.kbDebug("Home: hero picker item selected -> prepare crop")
            Task { await prepareHeroCrop(item: newItem) }
            Task { await bootstrapMyAvatarIfNeeded() }
        }
        .task(id: effectiveFamilyIdForAvatar) {
            await bootstrapMyAvatarIfNeeded()
        }
        
        // ✅ Cropper sheet
        .sheet(isPresented: $showHeroCropper) {
            HeroCropperSheet(
                data: pendingHeroImageData,
                initialCrop: initialCrop,
                isUploading: isUploadingHero,
                onCancel: {
                    KBLog.sync.kbDebug("Home: hero crop canceled")
                    showHeroCropper = false
                    pendingHeroImageData = nil
                    pickedHeroItem = nil
                },
                onSave: { crop in
                    KBLog.sync.kbDebug("Home: hero crop save tapped -> upload")
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
    
    @MainActor
    private func bootstrapMyAvatarIfNeeded() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let avatarData = myProfile?.avatarData, !avatarData.isEmpty { return }
        
        let fid = effectiveFamilyIdForAvatar
        let familyIdOrNil: String? = fid.isEmpty ? nil : fid
        
        do {
            let data = try await avatarRemoteStore.downloadAvatar(uid: uid, familyId: familyIdOrNil)
            let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
            let existing = try? modelContext.fetch(desc).first
            let profile = existing ?? KBUserProfile(uid: uid)
            if existing == nil { modelContext.insert(profile) }
            profile.avatarData = data
            profile.updatedAt = Date()
            try? modelContext.save()
            KBLog.app.kbDebug("Profile: avatar downloaded bytes=\(data.count)")
        } catch {
            KBLog.app.kbError("Profile: avatar download failed: \(error.localizedDescription)")
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
            KBLog.navigation.kbDebug("Home: navigate -> familySettings")
            coordinator.navigate(to: .familySettings)
        case .profile:
            KBLog.navigation.kbDebug("Home: navigate -> profile")
            coordinator.navigate(to: .profile)
        case .settings:
            KBLog.navigation.kbDebug("Home: navigate -> settings")
            coordinator.navigate(to: .settings)
        case .inviteCode:
            KBLog.navigation.kbDebug("Home: navigate -> inviteCode")
            coordinator.navigate(to: .inviteCode)
        case .calendar(let familyId):
            guard hasFamily else {
                KBLog.navigation.kbDebug("Home: navigation blocked (no family) -> FamilySettings")
                coordinator.navigate(to: .familySettings)
                return
            }
            KBLog.navigation.kbDebug("Home: navigate -> calendar(familyId: \(familyId))")
            coordinator.resetToRoot()
            coordinator.navigate(to: .calendar(familyId: familyId))
        default:
            if hasFamily {
                KBLog.navigation.kbDebug("Home: navigate -> \(String(describing: destination))")
                coordinator.navigate(to: destination.route)
            } else {
                KBLog.navigation.kbDebug("Home: navigation blocked (no family) -> FamilySettings")
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
                KBLog.sync.kbError("Home: hero picker loadTransferable returned nil")
                pickedHeroItem = nil
                return
            }
            pendingHeroImageData = data
            showHeroCropper = true
            KBLog.sync.kbInfo("Home: hero bytes loaded -> cropper opened (bytes=\(data.count))")
        } catch {
            heroUploadError = error.localizedDescription
            pickedHeroItem = nil
            KBLog.sync.kbError("Home: hero bytes load failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Step 2: upload + save crop
    
    @MainActor
    private func uploadHeroWithCrop(crop: HeroCrop) async {
        guard let familyId = activeFamily?.id, !familyId.isEmpty else {
            KBLog.sync.kbError("Home: uploadHeroWithCrop aborted (no familyId)")
            return
        }
        guard let data = pendingHeroImageData else {
            KBLog.sync.kbError("Home: uploadHeroWithCrop aborted (no pending image data)")
            return
        }
        guard !isUploadingHero else { return }
        
        isUploadingHero = true
        heroUploadError = nil
        KBLog.sync.kbInfo("Home: hero upload started familyId=\(familyId) bytes=\(data.count)")
        defer {
            isUploadingHero = false
            KBLog.sync.kbDebug("Home: hero upload finished (busy=false)")
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
                    KBLog.sync.kbInfo("Home: hero local update saved familyId=\(familyId)")
                } catch {
                    KBLog.sync.kbError("Home: hero local update failed: \(error.localizedDescription)")
                }
            }
            
            pendingHeroImageData = nil
            pickedHeroItem = nil
            showHeroCropper = false
            KBLog.sync.kbInfo("Home: hero upload OK familyId=\(familyId)")
            
        } catch {
            heroUploadError = error.localizedDescription
            KBLog.sync.kbError("Home: hero upload FAILED familyId=\(familyId) err=\(error.localizedDescription)")
        }
    }
}

// MARK: - HomeDestination

enum HomeDestination {
    case notes(familyId: String), todo, calendar(familyId: String), care
    case chat, document
    case expenses(familyId: String)
    case wallet(familyId: String)
    case passwords(familyId: String)
    case pets(familyId: String)
    case homeItems(familyId: String)
    case vehicles(familyId: String)
    case familyLocation(familyId: String), familyPhotos(familyId: String), familySettings
    case askExpert, profile, settings, inviteCode, shopping(familyId: String)
    case pediatric(familyId: String, childId: String)
    case travel(familyId: String)
    
    /// Mappa verso il Route dell'AppCoordinator.
    var route: Route {
        switch self {
        case .notes(let familyId):           return .notesHome(familyId: familyId)
        case .todo:                          return .todo
        case .calendar(let familyId):        return .calendar(familyId: familyId)
        case .care:                          return .familySettings  // legacy, non usato
        case .chat:                          return .chat
        case .document:                      return .document
        case .expenses(let familyId):        return .expensesHome(familyId: familyId)
        case .wallet(let familyId):          return .walletHome(familyId: familyId)
        case .passwords(let familyId):      return .passwordsHome(familyId: familyId)
        case .pets(let fid):                 return .petsHome(familyId: fid)
        case .homeItems(let fid):            return .homeItemsHome(familyId: fid)
        case .vehicles(let fid):             return .vehiclesHome(familyId: fid)
        case .familyLocation(let familyID):  return .familyLocation(familyId: familyID)
        case .familyPhotos(let familyId):    return .familyPhotos(familyId: familyId)
        case .familySettings:                return .familySettings
        case .askExpert:                     return .askExpert
        case .profile:                       return .profile
        case .settings:                      return .settings
        case .inviteCode:                    return .inviteCode
        case .shopping(let familyID):        return .shoppingList(familyId: familyID)
        case .pediatric(let fid, _):         return .pediatricChildSelector(familyId: fid)
        case .travel(let fid):               return .travelList(familyId: fid)
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
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .kbLocationSharingStateChanged)
            .receive(on: DispatchQueue.main)   // ← garantisce main thread
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        
        // ← NUOVO: polling leggero ogni 30s come safety net per le scadenze
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }
    
    func refresh() {
        let defaults = UserDefaults.standard
        var sharing = defaults.bool(forKey: KBLocationDefaults.isSharing)
        
        // Se c'è una scadenza e è già passata, considera la condivisione terminata
        if sharing {
            let expiresTimestamp = defaults.double(forKey: KBLocationDefaults.expiresAt)
            if expiresTimestamp > 0 {
                let expiresAt = Date(timeIntervalSince1970: expiresTimestamp)
                if expiresAt <= Date() {
                    // Scaduta: pulizia UserDefaults qui, il ViewModel non è attivo
                    defaults.set(false, forKey: KBLocationDefaults.isSharing)
                    defaults.removeObject(forKey: KBLocationDefaults.expiresAt)
                    sharing = false
                }
            }
        }
        
        if sharing != isSharing {
            isSharing = sharing
        }
    }
}

private enum HomeCardID: String, CaseIterable, Codable {
    case note
    case todo
    case shopping
    case calendar
    case care
    case chat
    case documents
    case expenses
    case wallet
    case passwords
    case location
    case photos
    case family
    case expert
    case pets
    case homeItems
    case vehicles
    case travel
}

// MARK: - HomeCardGrid

private struct HomeCardGrid: View {
    let hasFamily: Bool
    let familyId: String
    let onNavigate: (HomeDestination) -> Void
    
    @ObservedObject private var badge = BadgeManager.shared
    @ObservedObject private var subscriptionManager = KBSubscriptionManager.shared
    @StateObject private var locationObserver = LocationSharingObserver()
    @Query private var passwordEntries: [PasswordEntry]
    
    @State private var order: [HomeCardID] = []
    @State private var dragged: HomeCardID?
    @State private var showUpgrade = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(hasFamily: Bool, familyId: String, onNavigate: @escaping (HomeDestination) -> Void) {
        self.hasFamily = hasFamily
        self.familyId = familyId
        self.onNavigate = onNavigate
        let fid = familyId
        _passwordEntries = Query(
            filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
    }
    
    private var storageKey: String {
        // Ordine per famiglia (se presente), così ogni famiglia può avere un layout diverso
        let fam = familyId.isEmpty ? "nofamily" : familyId
        return "kb.home.cardOrder.\(fam)"
    }

    private var passwordHomeSecurityBadgeCount: Int {
        PasswordsHomeBadgeAck.homeBadgeCount(
            entries: passwordEntries,
            familyId: familyId,
            currentUid: Auth.auth().currentUser?.uid
        )
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(order, id: \.self) { id in
                cardView(for: id)
                    .homeCardMasked() // ✅ QUI, non dentro HomeCardView
                    .onDrag {
                        dragged = id
                        return NSItemProvider(object: id.rawValue as NSString)
                    } preview: {
                        cardView(for: id)
                            .homeCardMasked()
                            .drawingGroup() // più costosa, ma preview-only
                    }
                    .onDrop(of: [.text], delegate: HomeCardDropDelegate(
                        item: id,
                        items: $order,
                        dragged: $dragged,
                        onChanged: { persist() }
                    ))
            }      }
        .onAppear {
            if order.isEmpty {
                order = loadOrder() ?? defaultOrder()
            }
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
                .environmentObject(subscriptionManager)
        }
    }
    
    // MARK: - Views mapping
    
    @ViewBuilder
    private func cardView(for id: HomeCardID) -> some View {
        switch id {
        case .note:
            ZStack(alignment: .topTrailing) {
                HomeCardView(title: "Note", subtitle: "Appunti veloci", systemImage: "note.text", tint: .yellow) {
                    KBLog.navigation.kbDebug("Home: tap Notes")
                    FABUsageTracker.shared.record("note")
                    // reset badge note prima di navigare
                    Task { @MainActor in
                        BadgeManager.shared.clearNotes()
                        await CountersService.shared.reset(familyId: familyId, field: .notes)
                    }
                    onNavigate(.notes(familyId: familyId))
                }
                if badge.notes > 0 {
                    BadgeView(count: badge.notes)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .todo:
            ZStack(alignment: .topTrailing) {
                HomeCardView(title: "To-Do", subtitle: "Lista condivisa", systemImage: "checklist", tint: .blue) {
                    KBLog.navigation.kbDebug("Home: tap Todo")
                    FABUsageTracker.shared.record("todo")
                    onNavigate(.todo)
                }
                if badge.todos > 0 {
                    BadgeView(count: badge.todos)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .shopping:
            ZStack(alignment: .topTrailing) {
                HomeCardView(title: "Lista della Spesa", subtitle: "Lista condivisa", systemImage: "cart.fill", tint: .green) {
                    KBLog.navigation.kbDebug("Home: tap Shopping")
                    FABUsageTracker.shared.record("grocery")
                    // reset badge spesa prima di navigare
                    Task { @MainActor in
                        BadgeManager.shared.clearShopping()
                        await CountersService.shared.reset(familyId: familyId, field: .shopping)
                    }
                    onNavigate(.shopping(familyId: familyId))
                }
                if badge.shopping > 0 {
                    BadgeView(count: badge.shopping)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .calendar:
            ZStack(alignment: .topTrailing) {
                HomeCardView(title: "Calendario", subtitle: "Eventi e affidamenti", systemImage: "calendar", tint: .purple) {
                    KBLog.navigation.kbDebug("Home: tap Calendar")
                    FABUsageTracker.shared.record("event")
                    onNavigate(.calendar(familyId: familyId))
                }
                if badge.calendar > 0 {
                    BadgeView(count: badge.calendar)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .care:
            HomeCardView(title: "Salute", subtitle: "Health tracker", systemImage: "heart.fill", tint: .red) {
                KBLog.navigation.kbDebug("Home: tap Care")
                FABUsageTracker.shared.record("health")
                onNavigate(.pediatric(familyId: familyId, childId: ""))
            }
            
        case .chat:
            ZStack(alignment: .topTrailing) {
                HomeCardView(title: "Chat", subtitle: "Messaggi famiglia", systemImage: "message.fill", tint: .green) {
                    KBLog.navigation.kbDebug("Home: tap Chat")
                    FABUsageTracker.shared.record("chat")
                    onNavigate(.chat)
                }
                if badge.chat > 0 {
                    BadgeView(count: badge.chat)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .documents:
            ZStack(alignment: .topTrailing) {
                HomeCardView(title: "Documenti", subtitle: "Carte importanti", systemImage: "doc.text", tint: .orange) {
                    KBLog.navigation.kbDebug("Home: tap Documents")
                    FABUsageTracker.shared.record("documents")
                    onNavigate(.document)
                }
                if badge.documents > 0 {
                    BadgeView(count: badge.documents)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .expenses:
            HomeCardView(title: "Spese", subtitle: "Rette, visite, extra", systemImage: "eurosign.circle", tint: .mint) {
                KBLog.navigation.kbDebug("Home: tap Expenses")
                FABUsageTracker.shared.record("expense")
                Task {
                    BadgeManager.shared.clearExpenses()
                    await CountersService.shared.reset(familyId: familyId, field: .expenses)
                }
                onNavigate(.expenses(familyId: familyId))
            }
            .overlay(alignment: .topTrailing) {
                if badge.expenses > 0 {
                    BadgeView(count: badge.expenses)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            
        case .wallet:
            HomeCardView(title: "Wallet", subtitle: "Biglietti e prenotazioni", systemImage: "ticket.fill", tint: .indigo) {
                KBLog.navigation.kbDebug("Home: tap Wallet")
                FABUsageTracker.shared.record("wallet")
                Task {
                    BadgeManager.shared.clearWallet()
                    await CountersService.shared.reset(familyId: familyId, field: .wallet)
                }
                onNavigate(.wallet(familyId: familyId))
            }
            .overlay(alignment: .topTrailing) {
                if badge.wallet > 0 {
                    BadgeView(count: badge.wallet)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }

        case .passwords:
            // Card standard (come Documenti / Wallet / Salute): KBTheme via HomeCardView, nessun tema dedicato.
            HomeCardView(
                title: "Password",
                subtitle: "Credenziali di famiglia",
                systemImage: "key.fill",
                tint: Color(hex: "#5E5CE6") ?? .blue
            ) {
                KBLog.navigation.kbDebug("Home: tap Passwords")
                FABUsageTracker.shared.record("passwords")
                onNavigate(.passwords(familyId: familyId))
            }
            .overlay(alignment: .topTrailing) {
                if passwordHomeSecurityBadgeCount > 0 {
                    BadgeView(count: passwordHomeSecurityBadgeCount)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }

        case .location:
            ZStack {
                HomeCardView(title: "Posizione", subtitle: "Dove sono tutti", systemImage: "location.fill", tint: .cyan) {
                    KBLog.navigation.kbDebug("Home: tap FamilyLocation")
                    onNavigate(.familyLocation(familyId: familyId))
                }
                
                if badge.location > 0 {
                    VStack {
                        HStack { Spacer(); BadgeView(count: badge.location) }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                }
                
                if locationObserver.isSharing {
                    VStack {
                        Spacer()
                        HStack { Spacer(); LocationSharingPulse() }
                    }
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                }
            }
            
        case .photos:
            HomeCardView(title: "Foto e video", subtitle: "Album condiviso", systemImage: "photo.stack.fill", tint: .pink) {
                KBLog.navigation.kbDebug("Home: tap FamilyPhotos")
                onNavigate(.familyPhotos(familyId: familyId))
            }
            
        case .family:
            HomeCardView(title: "Family", subtitle: "Membri e inviti", systemImage: "person.2.fill", tint: .teal) {
                KBLog.navigation.kbDebug("Home: tap FamilySettings")
                onNavigate(.familySettings)
            }
            
        case .pets:
            HomeCardView(title: "Animali domestici", subtitle: "Cure e promemoria", systemImage: "pawprint.fill", tint: Color(hex: "#FF9500") ?? .orange) {
                KBLog.navigation.kbDebug("Home: tap Pets")
                FABUsageTracker.shared.record("pets")
                onNavigate(.pets(familyId: familyId))
            }

        case .homeItems:
            HomeCardView(title: "Casa", subtitle: "Garanzie e manutenzioni", systemImage: "house.fill", tint: Color(hex: "#8B6914") ?? .brown) {
                KBLog.navigation.kbDebug("Home: tap HomeItems")
                FABUsageTracker.shared.record("home_items")
                onNavigate(.homeItems(familyId: familyId))
            }

        case .vehicles:
            HomeCardView(title: "Garage", subtitle: "Auto e scadenze", systemImage: "car.fill", tint: Color(hex: "#1A1A1A") ?? .primary) {
                KBLog.navigation.kbDebug("Home: tap Vehicles")
                FABUsageTracker.shared.record("vehicles")
                onNavigate(.vehicles(familyId: familyId))
            }

        case .travel:
            let travelAI = subscriptionManager.currentPlan.includesAI
            if hasFamily {
                ZStack(alignment: .topTrailing) {
                    HomeCardView(
                        title: "Viaggi",
                        subtitle: travelAI ? "Pianifica con l'AI" : "Piano Pro o Max per l'AI",
                        systemImage: travelAI ? "suitcase.fill" : "lock.fill",
                        tint: travelAI ? .teal : .gray
                    ) {
                        KBLog.navigation.kbDebug("Home: tap Travel")
                        if travelAI {
                            onNavigate(.travel(familyId: familyId))
                        } else if subscriptionManager.isFamilyOwner {
                            showUpgrade = true
                        }
                    }
                    if !travelAI {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.gray.opacity(0.9))
                            .clipShape(Circle())
                            .padding(8)
                    }
                }
            } else {
                HomeCardView(title: "Viaggi", subtitle: "Pianifica con l'AI", systemImage: "suitcase.fill", tint: .teal) {
                    onNavigate(.familySettings)
                }
            }

        case .expert:
            let aiAvailable = subscriptionManager.currentPlan.includesAI
            ZStack(alignment: .topTrailing) {
                HomeCardView(
                    title: "Assistente",
                    subtitle: aiAvailable ? "Conosce salute, visite, esami, documenti, wallet e password" : "Disponibile con Pro o Max",
                    systemImage: aiAvailable ? "brain.head.profile" : "lock.fill",
                    tint: aiAvailable ? .purple : .gray
                ) {
                    KBLog.navigation.kbDebug("Home: tap AskExpert")
                    if aiAvailable {
                        onNavigate(.askExpert)
                    } else if subscriptionManager.isFamilyOwner {
                        showUpgrade = true
                    }
                }
                if !aiAvailable {
                    Image(systemName: "lock.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.gray))
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
        }
    }
    
    // MARK: - Order defaults + persistence
    
    private func defaultOrder() -> [HomeCardID] {
        // ordine iniziale (puoi cambiarlo quando vuoi)
        [.note, .todo, .shopping, .calendar, .care, .chat, .documents, .expenses, .wallet, .passwords, .location, .photos, .family, .expert, .travel, .pets, .homeItems, .vehicles]
    }
    
    private func loadOrder() -> [HomeCardID]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        do {
            let decoded = try JSONDecoder().decode([HomeCardID].self, from: data)
            // se in futuro aggiungi nuove card: le appendiamo
            let missing = defaultOrder().filter { !decoded.contains($0) }
            return decoded + missing
        } catch {
            return nil
        }
    }
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(order)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // niente log qui se non vuoi spam, ma volendo un debug una tantum puoi farlo
        }
    }
}

private struct HomeCardDropDelegate: DropDelegate {
    let item: HomeCardID
    @Binding var items: [HomeCardID]
    @Binding var dragged: HomeCardID?
    let onChanged: () -> Void
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // 👇 Questo fa sparire il "+" verde (copy) e lo trasforma in move
        DropProposal(operation: .move)
    }
    
    func dropEntered(info: DropInfo) {
        guard let dragged,
              dragged != item,
              let from = items.firstIndex(of: dragged),
              let to = items.firstIndex(of: item) else { return }
        
        withAnimation(.snappy) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        onChanged()
    }
    
    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

private struct HomeCardMask: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    let cornerRadius: CGFloat = 16
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .compositingGroup()
    }
}

private extension View {
    func homeCardMasked() -> some View { modifier(HomeCardMask()) }
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
