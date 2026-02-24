import SwiftUI
import MapKit
import SwiftData
import FirebaseAuth
import UIKit

// MARK: - Notification per aggiornamento nome da ProfileView
extension Notification.Name {
    static let kbProfileDisplayNameUpdated = Notification.Name("kbProfileDisplayNameUpdated")
}

struct FamilyLocationView: View {
    
    let familyId: String
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: FamilyLocationViewModel
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Tiene traccia degli ID già inclusi nel fit, così la camera non salta
    /// ad ogni aggiornamento di coordinate — solo quando arriva un ID nuovo.
    @State private var fittedUserIds: Set<String> = []
    
    @State private var showShareAlert = false
    @State private var showDurationSheet = false
    @State private var selectedHours = 2
    
    init(familyId: String) {
        self.familyId = familyId
        _viewModel = StateObject(wrappedValue: FamilyLocationViewModel(familyId: familyId))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            Map(position: $cameraPosition) {
                UserAnnotation()
                
                ForEach(viewModel.sharedUsers) { user in
                    Annotation("", coordinate: user.coordinate) {
                        AvatarMarker(
                            name: user.name,
                            avatarData: avatarDataFor(uid: user.id)
                        )
                    }
                }
            }
            .mapControls {
                MapCompass()
            }
            .ignoresSafeArea()
            // FIX: adatta la camera solo quando appare un ID nuovo
            .onChange(of: viewModel.sharedUsers) { _, users in
                fitCameraIfNeeded(users: users)
            }
            
            FindMyBottomCard(
                isSharing: viewModel.isSharing,
                myStatusLine: mySharingStatusLine,
                othersStatusLine: othersSharingLine,
                hasAnySharedPositions: !viewModel.sharedUsers.isEmpty,
                deviceName: "Questo iPhone",
                onToggleChanged: { isOn in
                    if isOn {
                        showShareAlert = true
                    } else {
                        Task { await viewModel.stopSharing() }
                    }
                }
            )
        }
        .navigationTitle("Posizione")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.start()
            syncDisplayNameToViewModel()
        }
        .onDisappear { viewModel.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .kbProfileDisplayNameUpdated)) { notification in
            if let name = notification.userInfo?["displayName"] as? String {
                viewModel.updateDisplayName(name)
            }
        }
        .alert("Condividi la tua posizione", isPresented: $showShareAlert) {
            Button("Tempo reale") {
                let name = myDisplayName()
                Task { await viewModel.startRealtime(displayName: name) }
            }
            Button("Temporaneamente") {
                showDurationSheet = true
            }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showDurationSheet) {
            durationSheet
        }
    }
    
    // MARK: - Camera fit
    
    private func fitCameraIfNeeded(users: [SharedUserLocation]) {
        let currentIds = Set(users.map { $0.id })
        // Esci se non ci sono ID nuovi rispetto all'ultimo fit
        guard !currentIds.subtracting(fittedUserIds).isEmpty else { return }
        fittedUserIds = currentIds
        
        guard !users.isEmpty else { return }
        
        // Coordinate remote + posizione device locale (se disponibile)
        var coordinates: [CLLocationCoordinate2D] = users.map { $0.coordinate }
        if let myCoord = CLLocationManager().location?.coordinate {
            coordinates.append(myCoord)
        }
        
        if coordinates.count == 1 {
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coordinates[0],
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                ))
            }
            return
        }
        
        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Padding 40% così i marker non finiscono sul bordo
        let latDelta = max((maxLat - minLat) * 1.4, 0.005)
        let lonDelta = max((maxLon - minLon) * 1.4, 0.005)
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            ))
        }
    }
    
    // MARK: - Sheet durata
    
    private var durationSheet: some View {
        VStack(spacing: 20) {
            Text("Condividi temporaneamente")
                .font(.title2)
                .bold()
            
            Picker("Durata", selection: $selectedHours) {
                Text("2 ore").tag(2)
                Text("3 ore").tag(3)
                Text("8 ore").tag(8)
            }
            .pickerStyle(.segmented)
            
            Button("Conferma") {
                let name = myDisplayName()
                Task { await viewModel.startTemporary(hours: selectedHours, displayName: name) }
                showDurationSheet = false
            }
            .buttonStyle(.borderedProminent)
            
            Button("Annulla", role: .cancel) {
                showDurationSheet = false
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
    
    // MARK: - Status lines
    
    private var mySharingStatusLine: String? {
        guard viewModel.isSharing else { return nil }
        switch viewModel.myMode {
        case .realtime:
            return "Stai condividendo la tua posizione"
        case .temporary:
            guard let expires = viewModel.myExpiresAt else { return "Stai condividendo temporaneamente" }
            return "Stai condividendo temporaneamente fino alle \(expires.formatted(date: .omitted, time: .shortened))"
        case .none:
            return nil
        }
    }
    
    private var othersSharingLine: String? {
        let myUid = Auth.auth().currentUser?.uid ?? ""
        let others = viewModel.sharedUsers.filter { $0.id != myUid }
        guard !others.isEmpty else { return nil }
        
        let parts = others.map { u in
            if u.mode == .temporary {
                if let exp = u.expiresAt {
                    return "\(u.name) sta condividendo temporaneamente fino alle \(exp.formatted(date: .omitted, time: .shortened))"
                } else {
                    return "\(u.name) sta condividendo temporaneamente"
                }
            } else {
                return "\(u.name) sta condividendo la posizione"
            }
        }
        
        if parts.count <= 2 { return parts.joined(separator: " • ") }
        return "\(parts.prefix(2).joined(separator: " • ")) • e altri \(parts.count - 2)"
    }
    
    // MARK: - SwiftData helpers
    
    private func myDisplayName() -> String {
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return "Utente" }
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        let profile = try? modelContext.fetch(desc).first
        let name = profile?.displayName ?? ""
        if !name.isEmpty && name != "Utente" { return name }
        let fn = (profile?.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = (profile?.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let composed = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
        return composed.isEmpty ? "Utente" : composed
    }
    
    private func syncDisplayNameToViewModel() {
        viewModel.updateDisplayName(myDisplayName())
    }
    
    private func avatarDataFor(uid: String) -> Data? {
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        let profile = try? modelContext.fetch(desc).first
        return profile?.avatarData
    }
}

// MARK: - Bottom card stile Find My

struct FindMyBottomCard: View {
    let isSharing: Bool
    let myStatusLine: String?
    let othersStatusLine: String?
    let hasAnySharedPositions: Bool
    let deviceName: String
    let onToggleChanged: (Bool) -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            
            HStack {
                Text("Io")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
            }
            
            if !hasAnySharedPositions {
                Text("Nessuna posizione condivisa")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                    Text("La mia posizione")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                }
                
                Divider().opacity(0.5)
                
                HStack {
                    Text("Condividi la mia posizione")
                        .font(.system(size: 17, weight: .regular))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { isSharing },
                        set: { onToggleChanged($0) }
                    ))
                    .labelsHidden()
                }
                
                if let myStatusLine, isSharing {
                    Text(myStatusLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                
                HStack {
                    Text("Condivisa da")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(deviceName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                if let othersStatusLine {
                    Text(othersStatusLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Marker

private struct AvatarMarker: View {
    let name: String
    let avatarData: Data?
    
    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let avatarData, let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().stroke(.quaternary, lineWidth: 1))
            
            Text(name)
                .font(.caption)
                .bold()
        }
    }
}
