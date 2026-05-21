import SwiftUI
import MapKit
import SwiftData
import FirebaseAuth
import FirebaseStorage
import UIKit

// MARK: - Notification per aggiornamento nome da ProfileView
extension Notification.Name {
    static let kbProfileDisplayNameUpdated = Notification.Name("kbProfileDisplayNameUpdated")
    static let kbLocationSharingStateChanged = Notification.Name("kbLocationSharingStateChanged")
}

struct FamilyLocationView: View {
    
    let familyId: String
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: FamilyLocationViewModel
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Tiene traccia degli ID già inclusi nel fit, così la camera non salta
    /// ad ogni aggiornamento di coordinate — solo quando arriva un ID nuovo.
    @State private var fittedUserIds: Set<String> = []
    
    /// ID del familiare che stiamo seguendo (nil = nessuno, modalità libera)
    @State private var followingUserId: String? = nil
    
    /// Altezza reale della bottom card, misurata a runtime tramite GeometryReader
    @State private var bottomCardHeight: CGFloat = 220
    
    /// Impedisce che il fit iniziale venga ripetuto ad ogni aggiornamento di coordinate
    @State private var hasPerformedInitialFit = false
    
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
                            avatarData: avatarDataFor(uid: user.id),
                            avatarURL: user.avatarURL,
                            isFollowed: followingUserId == user.id
                        )
                        .onTapGesture {
                            centerOn(user: user)
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
            }
            .ignoresSafeArea()
            // Quando l'utente muove manualmente la mappa, interrompi il follow
            .onMapCameraChange(frequency: .onEnd) { _ in
                // Non interrompere il follow se il movimento è stato causato da noi
                // (non c'è un modo nativo di distinguerlo, usiamo un approccio gesture-based
                //  tramite simultaneousGesture — vedi sotto)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        // L'utente sta trascinando la mappa manualmente → esci dal follow
                        if followingUserId != nil {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                followingUserId = nil
                            }
                        }
                    }
            )
            // Aggiorna camera quando cambiano gli utenti condivisi
            .onChange(of: viewModel.sharedUsers) { _, users in
                // Se stiamo seguendo qualcuno, mantieni il follow
                if let followId = followingUserId,
                   let followed = users.first(where: { $0.id == followId }) {
                    centerCamera(on: followed.coordinate, animated: true)
                    return
                }
                
                // Prima apertura con familiari già presenti:
                // centra subito su di loro, escludendo la posizione dell'utente
                // corrente se non sta condividendo (altrimenti la camera resterebbe
                // a metà strada tra lui e il familiare)
                if !hasPerformedInitialFit {
                    hasPerformedInitialFit = true
                    let myUid = Auth.auth().currentUser?.uid ?? ""
                    let isSharing = users.contains { $0.id == myUid }
                    let others = users.filter { $0.id != myUid }
                    
                    guard !others.isEmpty else { return }
                    
                    if others.count == 1 && !isSharing {
                        // Un solo familiare e io non condivido → vai diretto su di lui
                        centerCamera(on: others[0].coordinate, animated: true)
                    } else {
                        // Più familiari, oppure condivido anch'io → fit che include tutti
                        fitCamera(users: users, includeMyLocation: isSharing)
                    }
                    return
                }
                
                // Aggiornamenti successivi: fit solo se arriva un ID nuovo
                fitCameraIfNeeded(users: users)
            }
            
            // MARK: - Overlay bottoni riposizionamento
            // Posizionati in basso a destra, sopra la bottom card misurata a runtime
            .overlay(alignment: .bottomTrailing) {
                recentringButtons
                    .padding(.trailing, 16)
                    .padding(.bottom, bottomCardHeight + 16)
            }
            
            FindMyBottomCard(
                isSharing: viewModel.isSharing,
                myStatusLine: mySharingStatusLine,
                myCurrentAddress: viewModel.myCurrentAddress,
                othersStatusLine: othersSharingLine,
                hasAnySharedPositions: !viewModel.sharedUsers.isEmpty,
                deviceName: "Questo iPhone",
                onToggleChanged: { isOn in
                    if isOn {
                        showShareAlert = true
                    } else {
                        Task { await viewModel.stopSharing() }
                    }
                },
                onTapMyLocation: {
                    followingUserId = nil
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .userLocation(fallback: .automatic)
                    }
                }
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { bottomCardHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in bottomCardHeight = h }
                }
            )
        }
        .navigationTitle("Posizione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GeofenceListView(familyId: familyId)
                } label: {
                    Label("Zone di arrivo", systemImage: "mappin.and.ellipse")
                }
            }
        }
        .onAppear {
            BadgeManager.shared.activeSections.insert("location")
            viewModel.start()
            syncDisplayNameToViewModel()
            Task {
                await CountersService.shared.reset(familyId: familyId, field: .location)
            }
        }
        .onDisappear {
            viewModel.stop()
            BadgeManager.shared.activeSections.remove("location")
        }
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
    
    // MARK: - Bottoni overlay
    
    @ViewBuilder
    private var recentringButtons: some View {
        let myUid = Auth.auth().currentUser?.uid ?? ""
        let others = viewModel.sharedUsers.filter { $0.id != myUid }
        
        // Bottoni "Segui [nome]" — visibili solo se il familiare sta condividendo
        // (others contiene già solo chi è in sharedUsers, quindi solo chi condivide)
        VStack(spacing: 10) {
            ForEach(others) { user in
                Button {
                    if followingUserId == user.id {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            followingUserId = nil
                        }
                    } else {
                        centerOn(user: user)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: followingUserId == user.id ? "location.fill" : "location")
                            .font(.system(size: 13, weight: .semibold))
                        Text(user.name.components(separatedBy: " ").first ?? user.name)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        followingUserId == user.id
                        ? Color.orange
                        : Color(.systemBackground).opacity(0.92)
                    )
                    .foregroundStyle(followingUserId == user.id ? .white : .primary)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: others.count)
        .animation(.easeInOut(duration: 0.25), value: followingUserId)
    }
    
    // MARK: - Camera helpers
    
    /// Centra la camera su un familiare e avvia il follow
    private func centerOn(user: SharedUserLocation) {
        withAnimation(.easeInOut(duration: 0.2)) {
            followingUserId = user.id
        }
        centerCamera(on: user.coordinate, animated: true)
    }
    
    private func centerCamera(on coordinate: CLLocationCoordinate2D, animated: Bool) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }
    
    private func fitCameraIfNeeded(users: [SharedUserLocation]) {
        let currentIds = Set(users.map { $0.id })
        // Esci se non ci sono ID nuovi rispetto all'ultimo fit
        guard !currentIds.subtracting(fittedUserIds).isEmpty else { return }
        fittedUserIds = currentIds
        guard !users.isEmpty else { return }
        fitCamera(users: users, includeMyLocation: true)
    }
    
    /// Adatta la camera per mostrare tutti gli utenti indicati.
    /// `includeMyLocation` = true aggiunge anche la posizione GPS del device corrente.
    private func fitCamera(users: [SharedUserLocation], includeMyLocation: Bool) {
        var coordinates: [CLLocationCoordinate2D] = users.map { $0.coordinate }
        if includeMyLocation, let myCoord = CLLocationManager().location?.coordinate {
            coordinates.append(myCoord)
        }
        
        guard !coordinates.isEmpty else { return }
        
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
    let myCurrentAddress: String?
    let othersStatusLine: String?
    let hasAnySharedPositions: Bool
    let deviceName: String
    let onToggleChanged: (Bool) -> Void
    /// Tap sulla card "La mia posizione" → centra mappa su di me
    var onTapMyLocation: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 14) {
            
            HStack {
                Text("Io")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
            }
            
            // Indirizzo corrente se condivide, altrimenti "Nessuna posizione condivisa" in rosso
            if isSharing, let address = myCurrentAddress {
                Text(address)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if !isSharing {
                Text("Nessuna posizione condivisa")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // Header riga "La mia posizione" — tappabile per centrare su di me
                Button {
                    onTapMyLocation?()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSharing ? "location.fill" : "location.slash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSharing ? .blue : .secondary)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .animation(.easeInOut(duration: 0.3), value: isSharing)
                        Text("La mia posizione")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        // Chevron visivo per indicare che è tappabile
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
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
        .animation(.easeInOut(duration: 0.3), value: isSharing)
        .animation(.easeInOut(duration: 0.3), value: myCurrentAddress)
    }
}

// MARK: - Marker

private struct AvatarMarker: View {
    let name: String
    let avatarData: Data?
    let avatarURL: String?
    var isFollowed: Bool = false
    
    @State private var remoteImage: UIImage? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            avatarImage
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(
                        isFollowed ? Color.orange : Color(.quaternaryLabel),
                        lineWidth: isFollowed ? 3 : 1
                    )
                )
                .scaleEffect(isFollowed ? 1.15 : 1.0)
                .animation(.spring(response: 0.3), value: isFollowed)
            
            Text(name)
                .font(.caption)
                .bold()
        }
        .task(id: avatarURL) {
            await loadRemoteImageIfNeeded()
        }
    }
    
    @ViewBuilder
    private var avatarImage: some View {
        if let avatarData, let uiImage = UIImage(data: avatarData) {
            // Immagine locale SwiftData — priorità massima (è il mio stesso profilo)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let remoteImage {
            // Immagine scaricata da Firebase Storage SDK
            Image(uiImage: remoteImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFill()
                .foregroundStyle(.secondary)
        }
    }
    
    /// Scarica tramite Firebase Storage SDK (gestisce autenticazione automaticamente)
    private func loadRemoteImageIfNeeded() async {
        guard avatarData == nil,
              let avatarURL,
              let url = URL(string: avatarURL)
        else {
            print("AvatarMarker: skip download — avatarData=\(avatarData != nil) avatarURL=\(avatarURL ?? "nil")")
            return
        }
        
        print("AvatarMarker: downloading from \(avatarURL)")
        
        do {
            let ref = Storage.storage().reference(forURL: url.absoluteString)
            let data = try await ref.data(maxSize: 2 * 1024 * 1024)
            print("AvatarMarker: downloaded \(data.count) bytes")
            if let image = UIImage(data: data) {
                await MainActor.run { remoteImage = image }
                print("AvatarMarker: image set OK")
            } else {
                print("AvatarMarker: UIImage creation failed")
            }
        } catch {
            print("AvatarMarker: download failed — \(error.localizedDescription)")
        }
    }
}
