//
//  DevicesSettingsView.swift
//  KidBox
//
//  Dispositivi collegati all'account, con logout remoto.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Un documento `sessions/{id}` così com'è su Firestore, prima di raggruppare.
struct KBRawDeviceSession {
    let id: String
    let platform: String
    let deviceName: String
    let osVersion: String
    let lastSeenAt: Date?
}

/// Una riga dell'elenco: **un dispositivo**, non un documento.
///
/// I documenti in `users/{uid}/sessions` sono per *installazione* (vedi
/// `KBDeviceSessionRegistry.installId`): reinstallando l'app, o svuotandone i
/// dati, se ne crea uno nuovo e il vecchio resta lì. L'elenco mostrava così lo
/// stesso telefono due o tre volte, con date diverse. Qui le righe dello stesso
/// dispositivo diventano una sola, con la data di connessione più recente.
struct KBDeviceSession: Identifiable, Equatable {
    /// Tutti i documenti che appartengono a questo dispositivo, dal più recente.
    /// Servono interi: disconnetterlo deve cancellarli tutti, o il duplicato
    /// riapparirebbe al caricamento successivo.
    let sessionIds: [String]
    let platform: String
    let deviceName: String
    let osVersion: String
    let lastSeenAt: Date?

    var id: String { sessionIds.first ?? deviceName }

    var isCurrent: Bool { sessionIds.contains(KBDeviceSessionRegistry.installId) }

    var icon: String {
        switch platform {
        case "android": return "smartphone"
        case "web": return "globe"
        default: return deviceName == "iPad" ? "ipad" : (deviceName == "Mac" ? "desktopcomputer" : "iphone")
        }
    }
}

struct DevicesSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var sessions: [KBDeviceSession] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var pendingSignOut: KBDeviceSession?
    @State private var showSignOutAll = false
    @State private var isWorking = false

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

    var body: some View {
        List {
            Section {
                if isLoading && sessions.isEmpty {
                    HStack { ProgressView(); Text("Caricamento…").foregroundStyle(.secondary) }
                } else {
                    ForEach(sessions) { session in
                        row(session)
                    }
                }
            } footer: {
                Text("Tocca un dispositivo per disconnetterlo. Viene disconnesso appena è online: se è spento o senza rete, alla prima riapertura dell'app.")
            }
            .listRowBackground(cardBackground)

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .listRowBackground(cardBackground)
            }

            Section {
                Button(role: .destructive) {
                    showSignOutAll = true
                } label: {
                    Text("Esci da tutti i dispositivi")
                }
                .disabled(isWorking)
            } footer: {
                Text("Disconnette anche questo dispositivo. A differenza della disconnessione singola, questa è imposta dai server di Firebase: usala se temi che qualcun altro abbia accesso al tuo account, e cambia la password subito dopo.")
            }
            .listRowBackground(cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Dispositivi collegati")
        .task { await load() }
        .confirmationDialog(
            "Disconnettere questo dispositivo?",
            isPresented: Binding(get: { pendingSignOut != nil }, set: { if !$0 { pendingSignOut = nil } }),
            titleVisibility: .visible
        ) {
            Button("Disconnetti", role: .destructive) {
                if let session = pendingSignOut { Task { await signOut(session) } }
            }
            Button("Annulla", role: .cancel) { pendingSignOut = nil }
        } message: {
            if pendingSignOut?.isCurrent == true {
                Text("È il dispositivo che stai usando: uscirai subito da KidBox.")
            } else {
                Text("Dovrà accedere di nuovo per usare KidBox.")
            }
        }
        .confirmationDialog(
            "Uscire da tutti i dispositivi?",
            isPresented: $showSignOutAll,
            titleVisibility: .visible
        ) {
            Button("Esci da tutti", role: .destructive) { Task { await signOutAll() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Anche questo. Dovrai accedere di nuovo su ogni dispositivo.")
        }
    }

    private func row(_ session: KBDeviceSession) -> some View {
        Button {
            pendingSignOut = session
        } label: {
            HStack(spacing: 12) {
                Image(systemName: session.icon)
                    .foregroundStyle(KBTheme.bubbleTint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.deviceName).foregroundStyle(.primary)
                        if session.isCurrent {
                            Text("Questo dispositivo")
                                .font(.caption2)
                                .foregroundStyle(KBTheme.bubbleTint)
                        }
                    }
                    Text(subtitle(session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func subtitle(_ session: KBDeviceSession) -> String {
        guard let date = session.lastSeenAt else { return session.osVersion }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        // «Ultima apertura» e non «ultima attività»: il campo si aggiorna alla
        // registrazione della sessione, cioè all'avvio dell'app, non a ogni
        // gesto dell'utente. Dire di più sarebbe inventare.
        return String(
            format: NSLocalizedString("%@ · Ultima apertura %@", comment: ""),
            session.osVersion,
            fmt.string(from: date)
        )
    }

    // MARK: - Dati

    /// Raggruppa i documenti per dispositivo: stessa piattaforma e stesso nome
    /// sono la stessa macchina, e ne resta una riga sola con la connessione più
    /// recente. La versione di sistema non entra nella chiave: un aggiornamento
    /// di iOS non cambia il documento (viene riscritto in place), quindi
    /// tenerla dentro avrebbe solo rischiato di separare i duplicati veri.
    ///
    /// Il prezzo è dichiarato: due iPhone identici dello stesso utente
    /// finiscono in una riga sola. iOS non lascia leggere il nome che l'utente
    /// ha dato al telefono (vedi `KBDeviceSessionRegistry.deviceName`), quindi
    /// l'unica alternativa era continuare a mostrare le righe doppie.
    static func collapse(_ raw: [KBRawDeviceSession]) -> [KBDeviceSession] {
        var order: [String] = []
        var groups: [String: [KBRawDeviceSession]] = [:]

        for item in raw {
            let key = item.platform.lowercased() + "|"
                + item.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }

        return order.compactMap { key -> KBDeviceSession? in
            guard let items = groups[key] else { return nil }
            // Dal più recente: la prima riga detta data, versione e id mostrato.
            let sorted = items.sorted {
                ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast)
            }
            guard let newest = sorted.first else { return nil }
            return KBDeviceSession(
                sessionIds: sorted.map(\.id),
                platform: newest.platform,
                deviceName: newest.deviceName,
                osVersion: newest.osVersion,
                lastSeenAt: newest.lastSeenAt
            )
        }
    }

    private func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid).collection("sessions").getDocuments()
            let raw = snap.documents.map { d in
                KBRawDeviceSession(
                    id: d.documentID,
                    platform: d.get("platform") as? String ?? "",
                    deviceName: d.get("deviceName") as? String
                        ?? NSLocalizedString("Dispositivo", comment: ""),
                    osVersion: d.get("osVersion") as? String ?? "",
                    lastSeenAt: (d.get("lastSeenAt") as? Timestamp)?.dateValue()
                )
            }
            // Questo dispositivo in cima, poi i più recenti.
            sessions = Self.collapse(raw).sorted {
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
                return ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast)
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func signOut(_ session: KBDeviceSession) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        pendingSignOut = nil
        isWorking = true
        defer { isWorking = false }
        do {
            // Tutti i documenti del dispositivo, non solo quello mostrato: se ne
            // restasse indietro uno, la riga tornerebbe al prossimo caricamento
            // e quell'installazione resterebbe collegata.
            let sessionsRef = Firestore.firestore()
                .collection("users").document(uid).collection("sessions")
            for sessionId in session.sessionIds {
                try await sessionsRef.document(sessionId).delete()
            }

            if session.isCurrent {
                // Non si aspetta il proprio listener: il logout locale è già
                // deciso, e passare dal giro remoto lo renderebbe solo più
                // lento e dipendente dalla rete.
                await coordinator.signOut(modelContext: modelContext)
                return
            }
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func signOutAll() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await Functions.functions(region: "europe-west1")
                .httpsCallable("signOutAllDevices").call()
            await coordinator.signOut(modelContext: modelContext)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
