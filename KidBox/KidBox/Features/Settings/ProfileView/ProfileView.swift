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

struct ProfileView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Dynamic theme (same as LoginView / HomeView)
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    /// Background delle celle/sezioni della List
    private var cellBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    // Delete
    @State private var showDeleteAccountSheet = false
    @State private var deleteConfirmText = ""
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    
    // Alerts
    @State private var showSaveSuccessAlert = false
    @State private var showSaveErrorAlert = false
    
    // Profile fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var familyAddress: String = ""
    
    // Avatar
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    
    // Account info
    @State private var email: String = ""
    @State private var lastLoginAt: Date?
    
    // UI state
    @State private var saveErrorText: String?
    
    // Dirty tracking
    @State private var didLoadInitial = false
    @State private var isDirty = false
    
    // Snapshot of last saved values
    @State private var savedFirstName: String = ""
    @State private var savedLastName: String = ""
    @State private var savedFamilyAddress: String = ""
    @State private var savedAvatarHash: Int = 0
    
    @StateObject private var locationService = OneShotLocationService()
    
    private let locationRemoteStore = LocationRemoteStore()
    private let chatRemoteStore = ChatRemoteStore()
    private let avatarRemoteStore = AvatarRemoteStore()
    
    var body: some View {
        List {
            
            // MARK: - Profile
            Section("Profilo") {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        avatarView
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Seleziona foto profilo")
                    
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Nome", text: $firstName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        
                        TextField("Cognome", text: $lastName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(cellBackground)
                
                if isDirty {
                    Button {
                        KBLog.auth.debug("Profile: tap Save")
                        saveProfile()
                    } label: {
                        Text("Salva profilo")
                    }
                    .listRowBackground(cellBackground)
                }
                
                if let saveErrorText {
                    Text(saveErrorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowBackground(cellBackground)
                }
            }
            
            // MARK: - Family address
            Section("Famiglia") {
                TextField("Indirizzo famiglia", text: $familyAddress, axis: .vertical)
                    .lineLimit(2...4)
                    .listRowBackground(cellBackground)
                
                Button {
                    KBLog.app.debug("Profile: tap Detect Address")
                    detectFamilyAddress()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text(locationService.isWorking ? "Rilevamento..." : "Rileva da posizione")
                    }
                }
                .disabled(locationService.isWorking)
                .listRowBackground(cellBackground)
                
                if let locError = locationService.errorText {
                    Text(locError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowBackground(cellBackground)
                }
            }
            
            // MARK: - Account
            Section("Account") {
                if email.isEmpty {
                    Text("Email: —").foregroundStyle(.secondary)
                        .listRowBackground(cellBackground)
                } else {
                    Text("Email: \(email)")
                        .textSelection(.enabled)
                        .listRowBackground(cellBackground)
                }
                
                if let lastLoginAt {
                    Text("Ultimo login: \(lastLoginAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                        .listRowBackground(cellBackground)
                } else {
                    Text("Ultimo login: —")
                        .foregroundStyle(.secondary)
                        .listRowBackground(cellBackground)
                }
            }
            
            // MARK: - Actions
            Section {
                Button(role: .destructive) {
                    KBLog.auth.debug("Logout tap")
                    signOut()
                } label: {
                    Text("Logout")
                }
                .accessibilityLabel("Logout")
                .listRowBackground(cellBackground)
                
                Button(role: .destructive) {
                    deleteConfirmText = ""
                    deleteError = nil
                    showDeleteAccountSheet = true
                } label: {
                    Text("Elimina account")
                }
                .listRowBackground(cellBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Profilo")
        .onAppear {
            loadAuthInfo()
            loadLocalProfile()
            Task { await loadRemoteUserProfile() }
            syncSavedSnapshotFromCurrentState()
            didLoadInitial = true
            recomputeDirty()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        self.avatarData = data
                        self.saveErrorText = nil
                        if didLoadInitial {
                            recomputeDirty()
                        }
                    }
                }
            }
        }
        .onReceive(locationService.$resolvedAddress) { address in
            guard let address, !address.isEmpty else { return }
            familyAddress = address
            if didLoadInitial {
                recomputeDirty()
            }
        }
        .onChange(of: firstName) { _, _ in
            if didLoadInitial { recomputeDirty() }
        }
        .onChange(of: lastName) { _, _ in
            if didLoadInitial { recomputeDirty() }
        }
        .onChange(of: familyAddress) { _, _ in
            if didLoadInitial { recomputeDirty() }
        }
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
    }
    
    // MARK: - Avatar view
    private var avatarView: some View {
        Group {
            if let avatarData, let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().stroke(.quaternary, lineWidth: 1))
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
            avatarData = profile.avatarData
            
            if email.isEmpty { email = profile.email ?? "" }
            if lastLoginAt == nil { lastLoginAt = profile.lastLoginAt }
        }
    }
    
    private func resolvedFamilyId() -> String? {
        if let active = coordinator.activeFamilyId, !active.isEmpty {
            return active
        }
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try? modelContext.fetch(descriptor)
        return families?.first?.id
    }
    
    // MARK: - Dirty helpers
    private func syncSavedSnapshotFromCurrentState() {
        savedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        savedFamilyAddress = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        savedAvatarHash = avatarData?.hashValue ?? 0
    }
    
    private func recomputeDirty() {
        let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let avHash = avatarData?.hashValue ?? 0
        
        isDirty = (fn != savedFirstName) ||
        (ln != savedLastName) ||
        (addr != savedFamilyAddress) ||
        (avHash != savedAvatarHash)
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
            // 1) Upsert profilo locale (SwiftData)
            let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
            let existing = try modelContext.fetch(desc).first
            
            let profile: KBUserProfile
            if let existing {
                profile = existing
            } else {
                profile = KBUserProfile(uid: uid)
                modelContext.insert(profile)
            }
            
            profile.email = authEmail.ifEmpty(profile.email ?? "")
            profile.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.lastName  = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = (profile.lastName  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let full = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
            profile.displayName = full.isEmpty ? "Utente" : full
            
            profile.familyAddress = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.avatarData = avatarData
            
            profile.lastLoginAt = user.metadata.lastSignInDate ?? profile.lastLoginAt
            profile.updatedAt = Date()
            
            try modelContext.save()
            
            KBLog.auth.info("Profile saved (local) uid=\(uid, privacy: .public) displayName=\(profile.displayName ?? "nil", privacy: .public)")
            
            // 2) UI feedback
            saveErrorText = nil
            showSaveSuccessAlert = true
            
            // aggiorna snapshot "salvato" e nascondi bottone
            syncSavedSnapshotFromCurrentState()
            recomputeDirty()
            
            if let displayName = profile.displayName, !displayName.isEmpty, displayName != "Utente" {
                NotificationCenter.default.post(
                    name: .kbProfileDisplayNameUpdated,
                    object: nil,
                    userInfo: ["displayName": displayName]
                )
            }
            
            // 3) Remote sync (Firestore/Storage) - SEMPRE users/{uid}
            Task {
                // 3.a) Salva profilo utente globale (persistente tra logout/login)
                do {
                    try await Firestore.firestore()
                        .collection("users").document(uid)
                        .setData([
                            "firstName": profile.firstName ?? "",
                            "lastName": profile.lastName ?? "",
                            "displayName": profile.displayName ?? "",
                            "familyAddress": profile.familyAddress ?? "",
                            "email": profile.email ?? "",
                            "updatedAt": Timestamp(date: Date())
                        ], merge: true)
                    
                    KBLog.app.debug("Profile: saved to users/\(uid, privacy: .public)")
                } catch {
                    KBLog.app.error("Profile: users/\(uid, privacy: .public) save failed: \(error.localizedDescription, privacy: .public)")
                }
                
                // 2) ✅ upload avatar USER-scoped + salva avatarURL su users/{uid}
                if let avatarData = profile.avatarData {
                    do {
                        var avatarURL: String?
                        if let familyId = resolvedFamilyId(){
                            avatarURL = await avatarRemoteStore.uploadAvatar(imageData: avatarData, uid: uid, familyId: familyId)
                        } else {
                            avatarURL = await avatarRemoteStore.uploadUserAvatar(imageData: avatarData, uid: uid)
                        }
                        
                        try await Firestore.firestore()
                            .collection("users").document(uid)
                            .setData([
                                "avatarURL": avatarURL ?? "",
                                "updatedAt": Timestamp(date: Date())
                            ], merge: true)
                        
                        KBLog.app.debug("Profile: saved avatarURL to users/\(uid, privacy: .public)")
                    } catch {
                        KBLog.app.error("Profile: avatar upload failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                
                // 3.b) Aggiornamenti “family scoped” SOLO se abbiamo familyId
                guard !uid.isEmpty, let familyId = resolvedFamilyId() else {
                    KBLog.app.debug("Profile: skip family-scoped updates (missing familyId)")
                    return
                }
                
                await chatRemoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: profile.displayName ?? "")
                await locationRemoteStore.updateDisplayName(familyId: familyId, uid: uid, displayName: profile.displayName ?? "")
                
                // Aggiorna displayName nel members/{uid} della famiglia
                if let name = profile.displayName, !name.isEmpty, name != "Utente" {
                    do {
                        try await Firestore.firestore()
                            .collection("families").document(familyId)
                            .collection("members").document(uid)
                            .setData([
                                "displayName": name,
                                "updatedAt": Timestamp(date: Date())
                            ], merge: true)
                        
                        KBLog.app.debug("Profile: updated remote member displayName=\(name, privacy: .public)")
                    } catch {
                        KBLog.app.error("Profile: remote member name update failed: \(error.localizedDescription, privacy: .public)")
                    }
                    
                    // Aggiorna KBFamilyMember locale in SwiftData (main actor)
                    await MainActor.run {
                        let desc = FetchDescriptor<KBFamilyMember>(
                            predicate: #Predicate { $0.userId == uid && $0.familyId == familyId }
                        )
                        if let member = try? modelContext.fetch(desc).first {
                            member.displayName = name
                            member.updatedAt = Date()
                            try? modelContext.save()
                            KBLog.app.debug("Profile: updated local KBFamilyMember displayName=\(name, privacy: .public)")
                        }
                    }
                }
                
                // Upload avatar (family scoped nella tua implementazione attuale)
                if let avatarData = profile.avatarData {
                    await avatarRemoteStore.uploadAvatar(imageData: avatarData, uid: uid, familyId: familyId)
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
                if let v = remoteLastName,  !v.isEmpty { lastName = v }
                if let v = remoteAddress,   !v.isEmpty { familyAddress = v }
            }
            
            Task {
                guard let uid = Auth.auth().currentUser?.uid else { return }
                guard avatarData == nil else { return }
                
                let familyId = resolvedFamilyId() // può essere nil
                
                do {
                    let data = try await avatarRemoteStore.downloadAvatar(uid: uid, familyId: familyId)
                    await MainActor.run { avatarData = data }
                    KBLog.app.debug("Profile: avatar downloaded bytes=\(data.count, privacy: .public)")
                } catch {
                    KBLog.app.error("Profile: avatar download failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            // Aggiorna anche SwiftData (così resta cache locale)
            await MainActor.run {
                let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
                let existing = try? modelContext.fetch(desc).first
                let profile = existing ?? KBUserProfile(uid: uid)
                if existing == nil { modelContext.insert(profile) }
                
                profile.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.familyAddress = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.avatarData = avatarData
                profile.updatedAt = Date()
                try? modelContext.save()
                
                syncSavedSnapshotFromCurrentState()
                recomputeDirty()
            }
            
        } catch {
            KBLog.app.error("Profile: users/\(uid, privacy: .public) load failed: \(error.localizedDescription, privacy: .public)")
        }
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
                let mapItem = mapItems.first
                
                let formatted =
                mapItem?.address?.fullAddress
                ?? mapItem?.address?.shortAddress
                ?? ""
                
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
