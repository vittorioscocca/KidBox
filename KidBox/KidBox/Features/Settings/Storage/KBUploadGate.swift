//
//  KBUploadGate.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//

//
//  KBUploadGate.swift
//  KidBox
//
//  Helper centralizzato da usare in tutte le view che aprono un picker di upload.
//
//  UTILIZZO nelle view:
//
//  1. Aggiungi proprietà:
//       @Environment(\.modelContext) private var modelContext
//       @State private var showStorageUpgrade = false
//       private var familyId: String { ... }
//
//  2. Sul bottone che apre il picker:
//       Button { checkStorage { showSourcePicker = true } } label: { ... }
//
//  3. Nel body della view:
//       .storageUpgradeSheet($showStorageUpgrade)
//
//  Il check è sincrono e usa cachedUsedBytes (aggiornato da Firebase).

import SwiftUI
import SwiftData

// MARK: - View extension per lo sheet upgrade storage

extension View {
    /// Aggiunge il sheet UpgradeSheetView presentato quando showUpgrade = true.
    func storageUpgradeSheet(_ isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) {
            UpgradeSheetView()
                .environmentObject(KBSubscriptionManager.shared)
        }
    }
}

// MARK: - Funzione helper da usare nelle view

/// Controlla lo storage e, se ok, esegue `action`. Altrimenti imposta `showUpgrade = true`.
/// Usare nei bottoni che aprono picker di upload.
///
/// Esempio:
///     Button { checkUploadAllowed(modelContext: ctx, familyId: fid, showUpgrade: $showStorageUpgrade) { showPicker = true } }
func checkUploadAllowed(
    modelContext: ModelContext,
    familyId: String,
    showUpgrade: Binding<Bool>,
    action: () -> Void
) {
    let result = KBStorageGate.shared.canUpload(
        bytes: 0,
        modelContext: modelContext,
        familyId: familyId
    )
    switch result {
    case .allowed:
        action()
    case .blocked:
        showUpgrade.wrappedValue = true
    }
}
