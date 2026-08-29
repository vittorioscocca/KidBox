//
//  FamilyLeaveFlow.swift
//  KidBox
//
//  L'uscita dalla famiglia: gli avvisi che la governano e le azioni che ne
//  seguono.
//
//  Vive qui e non dentro una schermata perché l'uscita si può chiedere da due
//  posti — la card in Impostazioni e la schermata Famiglia — e le regole che
//  deve rispettare (unico membro, owner con altri membri, trasferimento) non
//  vanno riscritte due volte: una divergenza fra i due percorsi sarebbe un modo
//  per uscire senza passare dal trasferimento.
//

import SwiftUI
import Combine
import SwiftData

@MainActor
final class FamilyLeaveFlow: ObservableObject {
    @Published var showLeaveConfirm = false
    @Published var showOwnerOptions = false
    @Published var showOwnerAloneDelete = false
    @Published var showTransferSheet = false
    @Published var errorMessage: String?

    /// Gli altri membri, fotografati al momento del tap: la lista che il foglio
    /// di trasferimento mostrerà.
    @Published var transferCandidates: [KBFamilyMember] = []

    /// Sceglie la strada in base a chi sei e a quanti siete. È l'unico punto in
    /// cui questa decisione viene presa.
    func requestLeave(activeMembers: [KBFamilyMember], isOwner: Bool, currentUid: String) {
        transferCandidates = activeMembers.filter { $0.userId != currentUid }
        if activeMembers.count <= 1 {
            showOwnerAloneDelete = true
        } else if !isOwner {
            showLeaveConfirm = true
        } else {
            showOwnerOptions = true
        }
    }

    func leave(familyId: String, modelContext: ModelContext, coordinator: AppCoordinator) async {
        KBLog.sync.kbInfo("FamilyLeaveFlow: leaving familyId=\(familyId)")
        do {
            try await FamilyLeaveService(modelContext: modelContext).leaveFamily(familyId: familyId)
            KBLog.sync.kbInfo("FamilyLeaveFlow: leave OK familyId=\(familyId)")
            finish(coordinator)
        } catch {
            KBLog.sync.kbError("FamilyLeaveFlow: leave FAILED familyId=\(familyId) err=\(error.localizedDescription)")
            // Il servizio rifiuta l'uscita dell'unico membro: non è un errore da
            // mostrare, è l'altra strada — eliminare la famiglia.
            if error.localizedDescription.lowercased().contains("unico membro") {
                showOwnerAloneDelete = true
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func transferOwnershipAndLeave(
        familyId: String,
        newOwnerUid: String,
        modelContext: ModelContext,
        coordinator: AppCoordinator
    ) async {
        do {
            try await FamilyLeaveService(modelContext: modelContext)
                .transferOwnershipAndLeave(familyId: familyId, newOwnerUid: newOwnerUid)
            finish(coordinator)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFamily(familyId: String, modelContext: ModelContext, coordinator: AppCoordinator) async {
        do {
            try await FamilyLeaveService(modelContext: modelContext).deleteFamily(familyId: familyId)
            finish(coordinator)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Senza azzerare `activeFamilyId` resta puntato alla famiglia appena
    /// lasciata e `RootHostView` riattacca i listener su dati a cui non abbiamo
    /// più accesso.
    private func finish(_ coordinator: AppCoordinator) {
        coordinator.setActiveFamily(nil)
        coordinator.resetToRoot()
    }
}

// MARK: - Avvisi

extension View {
    /// Attacca gli avvisi dell'uscita dalla famiglia a una vista qualsiasi.
    func familyLeaveAlerts(
        _ flow: FamilyLeaveFlow,
        familyId: String?,
        modelContext: ModelContext,
        coordinator: AppCoordinator
    ) -> some View {
        modifier(FamilyLeaveAlerts(
            flow: flow,
            familyId: familyId,
            modelContext: modelContext,
            coordinator: coordinator
        ))
    }
}

private struct FamilyLeaveAlerts: ViewModifier {
    @ObservedObject var flow: FamilyLeaveFlow
    let familyId: String?
    let modelContext: ModelContext
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content
            .alert("Uscire dalla famiglia?", isPresented: $flow.showLeaveConfirm) {
                Button("Annulla", role: .cancel) { }
                Button("Esci", role: .destructive) { run { await flow.leave(familyId: $0, modelContext: modelContext, coordinator: coordinator) } }
            } message: {
                Text("Verrai rimosso dalla famiglia e tutti i dati associati verranno eliminati da questo dispositivo.")
            }
            .alert("Non puoi uscire ora", isPresented: $flow.showOwnerAloneDelete) {
                Button("Annulla", role: .cancel) { }
                Button("Elimina famiglia", role: .destructive) { run { await flow.deleteFamily(familyId: $0, modelContext: modelContext, coordinator: coordinator) } }
            } message: {
                Text("Sei l'unico membro. Per uscire devi eliminare la famiglia.")
            }
            .alert("Sei il creatore della famiglia", isPresented: $flow.showOwnerOptions) {
                Button("Trasferisci ownership") {
                    flow.showOwnerOptions = false
                    flow.showTransferSheet = true
                }
                Button("Elimina famiglia", role: .destructive) {
                    flow.showOwnerOptions = false
                    run { await flow.deleteFamily(familyId: $0, modelContext: modelContext, coordinator: coordinator) }
                }
                Button("Annulla", role: .cancel) { }
            } message: {
                Text("Prima di uscire puoi trasferire la ownership a un altro membro oppure eliminare la famiglia.")
            }
            .sheet(isPresented: $flow.showTransferSheet) {
                NavigationStack {
                    List(flow.transferCandidates) { member in
                        Button {
                            flow.showTransferSheet = false
                            run {
                                await flow.transferOwnershipAndLeave(
                                    familyId: $0,
                                    newOwnerUid: member.userId,
                                    modelContext: modelContext,
                                    coordinator: coordinator
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kbMemberLabel(member))
                                    .foregroundStyle(.primary)
                                Text(kbTrimmedNonEmpty(member.email) ?? member.userId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Nuovo owner")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Annulla") { flow.showTransferSheet = false }
                        }
                    }
                }
            }
            .alert("Errore", isPresented: Binding(
                get: { flow.errorMessage != nil },
                set: { if !$0 { flow.errorMessage = nil } }
            )) {
                Button("OK") { flow.errorMessage = nil }
            } message: {
                Text(flow.errorMessage ?? "")
            }
    }

    /// Senza famiglia non c'è niente da lasciare: l'azione si limita a non partire.
    private func run(_ action: @escaping (String) async -> Void) {
        guard let familyId, !familyId.isEmpty else { return }
        Task { @MainActor in await action(familyId) }
    }
}

// MARK: - Etichette

/// Nome e cognome del membro, con l'email come ripiego.
func kbMemberLabel(_ member: KBFamilyMember?) -> String {
    guard let member else { return String(localized: "questo membro") }
    return kbTrimmedNonEmpty(member.displayName)
        ?? kbTrimmedNonEmpty(member.email)
        ?? String(localized: "Utente")
}

func kbTrimmedNonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}
