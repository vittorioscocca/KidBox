//
//  ProfileView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import FirebaseAuth
import SwiftData
import PhotosUI
import CoreLocation
import MapKit
import OSLog
import Combine

struct ProfileView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    // Delete
    @State private var showDeleteAccountSheet = false
    @State private var deleteConfirmText = ""
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    
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
    @State private var saveInfoText: String?
    @State private var saveErrorText: String?
    
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
                
                Button {
                    KBLog.auth.debug("Profile: tap Save")
                    saveProfile()
                } label: {
                    Text("Salva profilo")
                }
                
                if let saveInfoText {
                    Text(saveInfoText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let saveErrorText {
                    Text(saveErrorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                
                Text("Il nome usato in chat viene preso da questo profilo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - Family address
            Section("Famiglia") {
                TextField("Indirizzo famiglia", text: $familyAddress, axis: .vertical)
                    .lineLimit(2...4)
                
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
                
                if let locError = locationService.errorText {
                    Text(locError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            
            // MARK: - Account (NO Firebase UID)
            Section("Account") {
                if email.isEmpty {
                    Text("Email: —")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Email: \(email)")
                        .textSelection(.enabled)
                }
                
                if let lastLoginAt {
                    Text("Ultimo login: \(lastLoginAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ultimo login: —")
                        .foregroundStyle(.secondary)
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
                
                Button(role: .destructive) {
                    deleteConfirmText = ""
                    deleteError = nil
                    showDeleteAccountSheet = true
                } label: {
                    Text("Elimina account")
                }
            }
        }
        .navigationTitle("Profilo")
        .onAppear {
            loadAuthInfo()
            loadLocalProfile()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        self.avatarData = data
                        self.saveInfoText = "Foto aggiornata."
                        self.saveErrorText = nil
                    }
                    await MainActor.run {
                        saveProfile()
                    }
                }
            }
        }
        .onReceive(locationService.$resolvedAddress) { address in
            guard let address, !address.isEmpty else { return }
            familyAddress = address
            saveProfile()
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
            
            // preferisci email da auth, ma se non c'è usa quella locale
            if email.isEmpty { email = profile.email ?? "" }
            if lastLoginAt == nil { lastLoginAt = profile.lastLoginAt }
        }
    }
    
    private func resolvedFamilyId() -> String? {
        
        // 1️⃣ Se il coordinator ha una famiglia attiva, usiamo quella
        if let active = coordinator.activeFamilyId, !active.isEmpty {
            return active
        }
        
        // 2️⃣ Fallback: prima famiglia salvata in locale
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try? modelContext.fetch(descriptor)
        
        return families?.first?.id
    }
    
    // MARK: - Save
    private func saveProfile() {
        guard let user = Auth.auth().currentUser else {
            saveErrorText = "Utente non autenticato."
            return
        }
        
        let uid = user.uid
        let authEmail = user.email ?? ""
        
        do {
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
            profile.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let full = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
            profile.displayName = full.isEmpty ? "Utente" : full
            
            profile.familyAddress = familyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.avatarData = avatarData
            
            // last login
            profile.lastLoginAt = user.metadata.lastSignInDate ?? profile.lastLoginAt
            profile.updatedAt = Date()
            
            // Salva SwiftData PRIMA di fare operazioni remote
            try modelContext.save()
            KBLog.auth.info("Profile saved uid=\(uid, privacy: .public) displayName=\(profile.displayName ?? "nil", privacy: .public)")
            
            // FIX: notifica FamilyLocationView (e qualsiasi altro observer) del nuovo nome
            // così il ViewModel aggiorna myCurrentDisplayName e Firestore in tempo reale.
            if let displayName = profile.displayName, !displayName.isEmpty, displayName != "Utente" {
                NotificationCenter.default.post(
                    name: .kbProfileDisplayNameUpdated,
                    object: nil,
                    userInfo: ["displayName": displayName]
                )
            }
            
            guard
                !uid.isEmpty,
                let familyId = resolvedFamilyId()
            else {
                KBLog.app.error("Profile remote update aborted: missing familyId")
                saveInfoText = "Salvato."
                saveErrorText = nil
                return
            }
            
            Task {
                await chatRemoteStore.setTyping(
                    false,
                    familyId: familyId,
                    uid: uid,
                    displayName: profile.displayName ?? ""
                )
                
                await locationRemoteStore.updateDisplayName(
                    familyId: familyId,
                    uid: uid,
                    displayName: profile.displayName ?? ""
                )
                
                // Carica avatar su Storage e salva URL in Firestore
                // così gli altri membri vedono la foto aggiornata sulla mappa
                if let avatarData = profile.avatarData {
                    await avatarRemoteStore.uploadAvatar(
                        imageData: avatarData,
                        uid: uid,
                        familyId: familyId
                    )
                }
            }
            
            saveInfoText = "Salvato."
            saveErrorText = nil
        } catch {
            saveErrorText = error.localizedDescription
            saveInfoText = nil
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
        } catch {
            KBLog.auth.error("Logout failed: \(error.localizedDescription, privacy: .public)")
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
    func ifEmpty(_ fallback: String) -> String {
        self.isEmpty ? fallback : self
    }
}
