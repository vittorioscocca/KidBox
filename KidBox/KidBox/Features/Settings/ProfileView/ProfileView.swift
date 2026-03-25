//
//  ProfileView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import SwiftData
import PhotosUI
import CoreLocation
import MapKit
import OSLog
import Combine
import StoreKit

// MARK: - AddressSearchCompleter

@MainActor
final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }
    
    func search(_ query: String) {
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        isSearching = true
        completer.queryFragment = query
    }
    
    func clear() {
        suggestions = []
        isSearching = false
        completer.queryFragment = ""
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isSearching = false
        suggestions = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        suggestions = []
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Theme
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.10, green: 0.10, blue: 0.11)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.16, green: 0.16, blue: 0.18)
        : Color(.systemBackground)
    }
    
    private var secondaryCardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.15)
        : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
    
    private var accent: Color { Color(red: 0.95, green: 0.38, blue: 0.10) }
    
    // MARK: - State
    @State private var showDeleteAccountSheet = false
    @State private var deleteConfirmText = ""
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showUpgradeSheet = false
    @State private var showSaveSuccessAlert = false
    @State private var showSaveErrorAlert = false
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var familyAddress: String = ""
    @State private var addressSearchText: String = ""
    @State private var showAddressSuggestions = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var email: String = ""
    @State private var lastLoginAt: Date?
    @State private var saveErrorText: String?
    @State private var didLoadInitial = false
    @State private var isDirty = false
    @State private var savedFirstName: String = ""
    @State private var savedLastName: String = ""
    @State private var savedFamilyAddress: String = ""
    @State private var savedAvatarHash: Int = 0
    @State private var showLogoutConfirm = false
    
    @StateObject private var addressCompleter = AddressSearchCompleter()
    @StateObject private var locationService = OneShotLocationService()
    
    private let locationRemoteStore = LocationRemoteStore()
    private let chatRemoteStore = ChatRemoteStore()
    private let avatarRemoteStore = AvatarRemoteStore()
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - Avatar + Nome
                    profileHeaderCard
                    
                    // MARK: - Indirizzo famiglia
                    familyAddressCard
                    
                    // MARK: - Account info
                    accountInfoCard
                    
                    // MARK: - Abbonamento
                    subscriptionCard
                    
                    // MARK: - Azioni
                    actionsCard
                    
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadAuthInfo()
            loadLocalProfile()
            Task { await loadRemoteUserProfile() }
            Task { await subscriptionManager.loadPlan() }
            syncSavedSnapshotFromCurrentState()
            didLoadInitial = true
            recomputeDirty()
            addressSearchText = familyAddress
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        self.avatarData = data
                        self.saveErrorText = nil
                        if didLoadInitial { recomputeDirty() }
                    }
                }
            }
        }
        .onReceive(locationService.$resolvedAddress) { address in
            guard let address, !address.isEmpty else { return }
            familyAddress = address
            addressSearchText = address
            addressCompleter.clear()
            showAddressSuggestions = false
            if didLoadInitial { recomputeDirty() }
        }
        .onChange(of: firstName) { _, _ in if didLoadInitial { recomputeDirty() } }
        .onChange(of: lastName)  { _, _ in if didLoadInitial { recomputeDirty() } }
        .onChange(of: familyAddress) { _, _ in if didLoadInitial { recomputeDirty() } }
        .alert("Profilo salvato ✅", isPresented: $showSaveSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nome, cognome e foto sono stati aggiornati.")
        }
        .alert("Errore salvataggio", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorText ?? "Errore sconosciuto")
        }
        .confirmationDialog("Esci dall'account?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { signOut() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Verrai reindirizzato alla schermata di accesso.")
        }
        .sheet(isPresented: $showDeleteAccountSheet) {
            DeleteAccountConfirmSheet(
                confirmText: $deleteConfirmText,
                isDeleting: $isDeletingAccount,
                errorText: $deleteError,
                onCancel: { showDeleteAccountSheet = false },
                onDelete: {
                    Task { @MainActor in
                        let normalized = deleteConfirmText
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .uppercased()
                        guard normalized == "ELIMINA" else {
                            deleteError = "Per confermare, digita ELIMINA."
                            return
                        }
                        isDeletingAccount = true
                        deleteError = nil
                        defer { isDeletingAccount = false }
                        do {
                            try await AccountDeletionService(modelContext: modelContext).deleteMyAccount()
                            showDeleteAccountSheet = false
                            coordinator.setActiveFamily(nil)
                            coordinator.resetToRoot()
                        } catch {
                            deleteError = error.localizedDescription
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showUpgradeSheet) {
            UpgradeSheetView()
                .environmentObject(subscriptionManager)
        }
    }
    
    // MARK: - Profile Header Card
    
    private var profileHeaderCard: some View {
        VStack(spacing: 0) {
            // Avatar
            HStack {
                Spacer()
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarView
                        Circle()
                            .fill(accent)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seleziona foto profilo")
                Spacer()
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider().padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                KBProfileField(icon: "person.fill", placeholder: "Nome", text: $firstName,
                               colorScheme: colorScheme, accent: accent)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                
                KBProfileField(icon: "person.fill", placeholder: "Cognome", text: $lastName,
                               colorScheme: colorScheme, accent: accent)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            if let saveErrorText {
                Text(saveErrorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            
            if isDirty {
                Button(action: {
                    KBLog.auth.debug("Profile: tap Save")
                    saveProfile()
                }) {
                    Label("Salva modifiche", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: isDirty)
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Family Address Card
    
    private var familyAddressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "house.fill", title: "Indirizzo famiglia")
            
            Divider().padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                // Campo di ricerca indirizzo
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    TextField("Cerca indirizzo...", text: $addressSearchText)
                        .font(.system(size: 15))
                        .onChange(of: addressSearchText) { _, newValue in
                            familyAddress = newValue
                            if newValue.count > 2 {
                                addressCompleter.search(newValue)
                                showAddressSuggestions = true
                            } else {
                                addressCompleter.clear()
                                showAddressSuggestions = false
                            }
                            if didLoadInitial { recomputeDirty() }
                        }
                    
                    if !addressSearchText.isEmpty {
                        Button {
                            addressSearchText = ""
                            familyAddress = ""
                            addressCompleter.clear()
                            showAddressSuggestions = false
                            if didLoadInitial { recomputeDirty() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                
                // Suggerimenti autocomplete
                if showAddressSuggestions && !addressCompleter.suggestions.isEmpty {
                    Divider().padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        ForEach(Array(addressCompleter.suggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                let full = suggestion.title + (suggestion.subtitle.isEmpty ? "" : ", \(suggestion.subtitle)")
                                addressSearchText = full
                                familyAddress = full
                                addressCompleter.clear()
                                showAddressSuggestions = false
                                if didLoadInitial { recomputeDirty() }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(accent)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.primary)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                index % 2 == 0
                                ? Color.clear
                                : secondaryCardBackground.opacity(0.5)
                            )
                            
                            if index < min(4, addressCompleter.suggestions.count - 1) {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .background(cardBackground)
                }
                
                // Pulsante rileva posizione
                Divider().padding(.horizontal, 16)
                
                Button {
                    KBLog.app.debug("Profile: tap Detect Address")
                    detectFamilyAddress()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: locationService.isWorking ? "location.fill.viewfinder" : "location.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)
                            .symbolEffect(.pulse, isActive: locationService.isWorking)
                        
                        Text(locationService.isWorking ? "Rilevamento in corso..." : "Usa la mia posizione attuale")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(accent)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(locationService.isWorking)
                
                if let locError = locationService.errorText {
                    Text(locError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Account Info Card
    
    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "person.badge.key.fill", title: "Account")
            
            Divider().padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                accountRow(
                    icon: "envelope.fill",
                    iconColor: Color(red: 0.2, green: 0.6, blue: 0.9),
                    label: "Email",
                    value: email.isEmpty ? "—" : email
                )
                
                Divider().padding(.leading, 52)
                
                accountRow(
                    icon: "clock.fill",
                    iconColor: Color(red: 0.4, green: 0.75, blue: 0.4),
                    label: "Ultimo accesso",
                    value: lastLoginAt?.formatted(date: .abbreviated, time: .shortened) ?? "—"
                )
            }
            .padding(.vertical, 4)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Subscription Card
    
    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "star.fill", title: "Abbonamento")
            
            Divider().padding(.horizontal, 16)
            
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(subscriptionPlanColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: subscriptionPlanIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(subscriptionPlanColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Piano \(subscriptionManager.currentPlan.displayName)")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 4) {
                        Text(subscriptionManager.currentPlan.storageLabel + " storage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if subscriptionManager.currentPlan.includesAI {
                            Text("·").foregroundStyle(.secondary)
                            Text("\(subscriptionManager.currentPlan.aiDailyLimit) msg AI/giorno")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if subscriptionManager.currentPlan != .max {
                    Button { showUpgradeSheet = true } label: {
                        Text("Upgrade")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color(red: 0.35, green: 0.6, blue: 0.85)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider().padding(.horizontal, 16)
            
            NavigationLink {
                StorageUsageView()
                    .environmentObject(subscriptionManager)
            } label: {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("Gestisci spazio e piani")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(spacing: 0) {
            // Esci
            Button {
                showLogoutConfirm = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(red: 1.0, green: 0.58, blue: 0.0).opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.0))
                    }
                    
                    Text("Esci")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Esci dall'account")
            
            Divider().padding(.leading, 66)
            
            // Elimina account
            Button {
                deleteConfirmText = ""
                deleteError = nil
                showDeleteAccountSheet = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.crop.circle.badge.minus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    
                    Text("Elimina account")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.red)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Reusable Components
    
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .kerning(0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func accountRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
            }
            .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Avatar View
    
    private var avatarView: some View {
        Group {
            if let avatarData, let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                        .foregroundStyle(accent.opacity(0.6))
                }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.6), accent.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
        )
        .shadow(color: accent.opacity(0.25), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Subscription Helpers
    
    private var subscriptionPlanColor: Color {
        switch subscriptionManager.currentPlan {
        case .free: return .gray
        case .pro:  return Color(red: 0.35, green: 0.6, blue: 0.85)
        case .max:  return Color(red: 0.55, green: 0.35, blue: 0.9)
        }
    }
    
    private var subscriptionPlanIcon: String {
        switch subscriptionManager.currentPlan {
        case .free: return "person.circle"
        case .pro:  return "star.circle.fill"
        case .max:  return "crown.fill"
        }
    }
    
    // MARK: - Load
    
    private func loadAuthInfo() {
        let user = Auth.auth().currentUser
        email = user?.email ?? ""
        lastLoginAt = user?.metadata.lastSignInDate
        KBLog.auth.debug("ProfileView appeared authed=\((user != nil), privacy: .public)")
    }
    
    private func loadLocalProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        if let profile = try? modelContext.fetch(desc).first {
            firstName = profile.firstName ?? ""
            lastName = profile.lastName ?? ""
            familyAddress = profile.familyAddress ?? ""
            addressSearchText = familyAddress
            avatarData = profile.avatarData
            if email.isEmpty { email = profile.email ?? "" }
            if lastLoginAt == nil { lastLoginAt = profile.lastLoginAt }
        }
    }
    
    private func resolvedFamilyId() -> String? {
        if let active = coordinator.activeFamilyId, !active.isEmpty { return active }
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try? modelContext.fetch(descriptor)
        return families?.first?.id
    }
    
    // MARK: - Dirty Helpers
    
    private func syncSavedSnapshotFromCurrentState() {
        savedFirstName     = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLastName      = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        savedFamilyAddress = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        savedAvatarHash    = avatarData?.hashValue ?? 0
    }
    
    private func recomputeDirty() {
        let fn     = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ln     = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr   = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let avHash = avatarData?.hashValue ?? 0
        isDirty = (fn != savedFirstName) || (ln != savedLastName) ||
        (addr != savedFamilyAddress) || (avHash != savedAvatarHash)
    }
    
    // MARK: - Save
    
    private func saveProfile() {
        guard let user = Auth.auth().currentUser else {
            saveErrorText = "Utente non autenticato."
            showSaveErrorAlert = true
            return
        }
        
        let uid = user.uid
        let authEmail = user.email ?? ""
        
        do {
            let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
            let existing = try modelContext.fetch(desc).first
            let profile: KBUserProfile
            if let existing { profile = existing } else {
                profile = KBUserProfile(uid: uid)
                modelContext.insert(profile)
            }
            
            profile.email       = authEmail.ifEmpty(profile.email ?? "")
            profile.firstName   = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.lastName    = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fn   = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ln   = (profile.lastName  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let full = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
            profile.displayName    = full.isEmpty ? "Utente" : full
            profile.familyAddress  = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.avatarData     = avatarData
            profile.lastLoginAt    = user.metadata.lastSignInDate ?? profile.lastLoginAt
            profile.updatedAt      = Date()
            
            try modelContext.save()
            KBLog.auth.info("Profile saved (local) uid=\(uid, privacy: .public)")
            
            saveErrorText = nil
            showSaveSuccessAlert = true
            syncSavedSnapshotFromCurrentState()
            recomputeDirty()
            
            if let displayName = profile.displayName, !displayName.isEmpty, displayName != "Utente" {
                NotificationCenter.default.post(
                    name: .kbProfileDisplayNameUpdated,
                    object: nil,
                    userInfo: ["displayName": displayName]
                )
            }
            
            Task {
                do {
                    try await Firestore.firestore()
                        .collection("users").document(uid)
                        .setData([
                            "firstName":     profile.firstName ?? "",
                            "lastName":      profile.lastName ?? "",
                            "displayName":   profile.displayName ?? "",
                            "familyAddress": profile.familyAddress ?? "",
                            "email":         profile.email ?? "",
                            "updatedAt":     Timestamp(date: Date())
                        ], merge: true)
                    KBLog.app.debug("Profile: saved to users/\(uid, privacy: .public)")
                } catch {
                    KBLog.app.error("Profile: users/\(uid, privacy: .public) save failed: \(error.localizedDescription, privacy: .public)")
                }
                
                if let avatarData = profile.avatarData {
                    do {
                        var avatarURL: String?
                        if let familyId = resolvedFamilyId() {
                            avatarURL = await avatarRemoteStore.uploadAvatar(imageData: avatarData, uid: uid, familyId: familyId)
                        } else {
                            avatarURL = await avatarRemoteStore.uploadUserAvatar(imageData: avatarData, uid: uid)
                        }
                        try await Firestore.firestore()
                            .collection("users").document(uid)
                            .setData(["avatarURL": avatarURL ?? "", "updatedAt": Timestamp(date: Date())], merge: true)
                    } catch {
                        KBLog.app.error("Profile: avatar upload failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                
                guard !uid.isEmpty, let familyId = resolvedFamilyId() else { return }
                await chatRemoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: profile.displayName ?? "")
                await locationRemoteStore.updateDisplayName(familyId: familyId, uid: uid, displayName: profile.displayName ?? "")
                
                if let name = profile.displayName, !name.isEmpty, name != "Utente" {
                    do {
                        try await Firestore.firestore()
                            .collection("families").document(familyId)
                            .collection("members").document(uid)
                            .setData(["displayName": name, "updatedAt": Timestamp(date: Date())], merge: true)
                        
                        let desc2 = FetchDescriptor<KBFamilyMember>(
                            predicate: #Predicate { $0.userId == uid && $0.familyId == familyId }
                        )
                        await MainActor.run {
                            if let member = try? modelContext.fetch(desc2).first {
                                member.displayName = name
                                member.updatedAt = Date()
                                try? modelContext.save()
                            }
                        }
                    } catch {
                        KBLog.app.error("Profile: remote member name update failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            saveErrorText = error.localizedDescription
            showSaveErrorAlert = true
            KBLog.auth.error("Profile save FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Location
    private func detectFamilyAddress() {
        locationService.requestAddress()
    }
    
    // MARK: - Logout
    private func signOut() {
        do {
            try Auth.auth().signOut()
            KBLog.auth.info("Logout OK")
            coordinator.resetToRoot()
            coordinator.signOut(modelContext: modelContext)
        } catch {
            KBLog.auth.error("Logout failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func loadRemoteUserProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }
            let remoteFirstName = data["firstName"] as? String
            let remoteLastName  = data["lastName"] as? String
            let remoteAddress   = data["familyAddress"] as? String
            await MainActor.run {
                if let v = remoteFirstName, !v.isEmpty { firstName = v }
                if let v = remoteLastName,  !v.isEmpty { lastName  = v }
                if let v = remoteAddress,   !v.isEmpty {
                    familyAddress    = v
                    addressSearchText = v
                }
            }
            Task {
                guard let uid = Auth.auth().currentUser?.uid else { return }
                guard avatarData == nil else { return }
                let familyId = resolvedFamilyId()
                do {
                    let data = try await avatarRemoteStore.downloadAvatar(uid: uid, familyId: familyId)
                    await MainActor.run { avatarData = data }
                } catch {
                    KBLog.app.error("Profile: avatar download failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            await MainActor.run {
                let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
                let existing = try? modelContext.fetch(desc).first
                let profile  = existing ?? KBUserProfile(uid: uid)
                if existing == nil { modelContext.insert(profile) }
                profile.firstName     = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.lastName      = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.familyAddress = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.avatarData    = avatarData
                profile.updatedAt     = Date()
                try? modelContext.save()
                syncSavedSnapshotFromCurrentState()
                recomputeDirty()
            }
        } catch {
            KBLog.app.error("Profile: users/\(uid, privacy: .public) load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - KBProfileField

private struct KBProfileField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let colorScheme: ColorScheme
    let accent: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark
                      ? Color(red: 0.12, green: 0.12, blue: 0.14)
                      : Color(red: 0.96, green: 0.96, blue: 0.97))
        )
    }
}

// MARK: - OneShotLocationService

@MainActor
final class OneShotLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var resolvedAddress: String?
    @Published var errorText: String?
    @Published var isWorking: Bool = false
    
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestAddress() {
        errorText = nil
        resolvedAddress = nil
        isWorking = true
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            isWorking = false
            errorText = "Permesso posizione negato. Abilitalo in Impostazioni."
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            manager.requestLocation()
        @unknown default:
            isWorking = false
            errorText = "Stato autorizzazione posizione non supportato."
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            isWorking = false
            errorText = "Permesso posizione negato."
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isWorking = false
        errorText = error.localizedDescription
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            isWorking = false
            errorText = "Posizione non disponibile."
            return
        }
        Task {
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    await MainActor.run {
                        self.isWorking = false
                        self.errorText = "Impossibile creare la richiesta di reverse geocoding."
                    }
                    return
                }
                let mapItems = try await request.mapItems
                let mapItem  = mapItems.first
                let formatted = mapItem?.address?.fullAddress ?? mapItem?.address?.shortAddress ?? ""
                await MainActor.run {
                    self.resolvedAddress = formatted.isEmpty ? nil : formatted
                    self.isWorking = false
                    self.errorText = formatted.isEmpty ? "Indirizzo non trovato." : nil
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.errorText = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Small helper
private extension String {
    func ifEmpty(_ fallback: String) -> String { self.isEmpty ? fallback : self }
}
