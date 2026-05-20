//
//  AppleHealthAppView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

/// Abbinamento e visualizzazione dati da Apple Salute (card «Apple App Salute»).
struct AppleHealthAppView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let familyId: String
    let childId: String

    @Query private var children: [KBChild]

    @State private var snapshot: KBHealthImportSnapshot?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showError = false
    @State private var showSuccess = false

    private let healthService = KBHealthKitService.shared

    private var child: KBChild? { children.first { $0.id == childId } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let snapshot {
                    AppleHealthDashboardView(
                        snapshot: snapshot,
                        childAgeDescription: childProfileAge,
                        childWeightKg: child?.weightKg
                    )
                } else {
                    connectPrompt
                }

                actionButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Apple App Salute")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { snapshot = KBHealthLinkStore.load(childId: childId) }
        .alert("Collegamento Salute", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Operazione non riuscita.")
        }
        .alert("Abbinamento aggiornato", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("I dati sono stati letti da Apple Salute.")
        }
    }

    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId = childId
        let cid = childId
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
    }

    /// Età calcolata dalla data di nascita in Salute (snapshot), allineata alla scheda medica.
    private var childProfileAge: String? {
        snapshot?.ageDescription
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.35, blue: 0.45).opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.45))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Dati da Apple Salute")
                    .font(.title3.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text("Passi, cuore, pressione, ossigeno, ECG e allenamenti sincronizzati da questo iPhone.")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
        }
    }

    private var connectPrompt: some View {
        VStack(spacing: 12) {
            Text("Non ancora collegato")
                .font(.subheadline.weight(.semibold))
            Text("Tocca il pulsante sotto per importare le metriche dall'app Salute.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KBTheme.cardBackground(colorScheme))
        )
    }

    private var actionButton: some View {
        Button {
            Task { await connectAndImport() }
        } label: {
            HStack {
                if isImporting {
                    ProgressView()
                        .tint(.white)
                }
                Text(snapshot == nil ? "Collega Apple Salute" : "Aggiorna dati")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.95, green: 0.35, blue: 0.45))
        .disabled(isImporting || !healthService.isAvailable)
        .padding(.bottom, 8)
    }

    private func connectAndImport() async {
        guard healthService.isAvailable else {
            importError = KBHealthKitError.notAvailable.errorDescription
            showError = true
            return
        }

        isImporting = true
        importError = nil
        defer { isImporting = false }

        do {
            try await healthService.requestAuthorization()
            let imported = try await healthService.fetchSnapshot()
            KBHealthLinkStore.save(imported, childId: childId)
            snapshot = imported
            applyImportedToChild(imported)
            showSuccess = true
        } catch {
            importError = error.localizedDescription
            showError = true
        }
    }

    private func applyImportedToChild(_ imported: KBHealthImportSnapshot) {
        guard let child else { return }
        var changed = false
        if let weight = imported.weightKg {
            child.weightKg = weight
            changed = true
        }
        if let dob = imported.birthDate {
            child.birthDate = dob
            changed = true
        }
        guard changed else { return }
        child.updatedAt = Date()
        child.updatedBy = Auth.auth().currentUser?.uid
        try? modelContext.save()
        Task { try? await ChildSyncService().upsert(child: child) }
    }
}
