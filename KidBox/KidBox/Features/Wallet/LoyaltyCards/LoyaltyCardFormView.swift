//
//  LoyaltyCardFormView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Inserimento manuale del numero carta + descrizione opzionale. Riusato sia
//  per un brand noto (dal catalogo) sia per il flusso "carta non in elenco",
//  dove mostra anche nome negozio + color picker.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct LoyaltyCardFormView: View {
    let familyId: String
    /// `nil` per il flusso "carta non in elenco".
    let brand: LoyaltyCardBrand?
    let prefilledCardNumber: String?
    let prefilledBarcodeFormat: String?
    let onSaved: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var cardNumber: String = ""
    @State private var note: String = ""
    @State private var storeName: String = ""
    @State private var selectedColor: Color = Color.loyaltyCardColor(hex: "#5856D6")
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isManualBrand: Bool { brand == nil }

    private var trimmedCardNumber: String {
        cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !trimmedCardNumber.isEmpty else { return false }
        if isManualBrand {
            return !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        Form {
            if isManualBrand {
                Section("Negozio") {
                    TextField("Nome negozio", text: $storeName)
                    ColorPicker("Colore carta", selection: $selectedColor, supportsOpacity: false)
                }
            }

            Section("Numero carta") {
                TextField("Numero carta", text: $cardNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
            }

            Section("Descrizione (opzionale)") {
                TextField("Es. tessera intestata a...", text: $note, axis: .vertical)
                    .lineLimit(1...3)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(brand?.name ?? NSLocalizedString("Nuova carta", comment: "Fallback nav title for a new loyalty card form when no brand is set"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Salva")
                    }
                }
                .disabled(!canSave || isSaving)
            }
        }
        .onAppear {
            if let prefilledCardNumber, cardNumber.isEmpty {
                cardNumber = prefilledCardNumber
            }
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let uid = Auth.auth().currentUser?.uid ?? "local"
        let displayName = Auth.auth().currentUser?.displayName ?? ""

        let resolvedBrandName = brand?.name ?? storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedPrimaryColor = brand?.primaryColorHex ?? selectedColor.toHexString()
        var resolvedSecondaryColor = brand?.secondaryColorHex ?? selectedColor.toHexString()
        let resolvedFormat = prefilledBarcodeFormat ?? brand?.defaultBarcodeFormat ?? "code128"
        // Congeliamo il logo del brand sulla carta: se domani il catalogo
        // cambia URL o rimuove il brand, la carta salvata resta coerente.
        let resolvedLogoURL = brand?.logoURL

        // Colori derivati dal logo REALE del brand, calcolati UNA VOLTA SOLA
        // qui alla creazione e poi persistiti/sincronizzati: così la card ha i
        // colori del logo che mostra, senza ricalcoli a ogni render (costosi e
        // fonte di sfarfallio) e con lo stesso identico aspetto per tutti i
        // membri della famiglia.
        //
        // Se il logo non si scarica (offline), non si legge, o il colore
        // estratto è troppo slavato/chiaro per reggere il testo bianco della
        // tile, `palette(fromLogoURL:)` restituisce nil e restano i colori
        // curati del catalogo — verificati, non vanno peggiorati. Il timeout
        // breve garantisce che il salvataggio non si blocchi mai per il logo.
        // Il flusso "carta non in elenco" (brand == nil) non è toccato: lì il
        // colore lo sceglie l'utente col ColorPicker.
        if brand != nil,
           let palette = await LoyaltyCardColorExtractor.palette(fromLogoURL: resolvedLogoURL, timeout: 3.0) {
            resolvedPrimaryColor = palette.primaryHex
            resolvedSecondaryColor = palette.secondaryHex
        }

        let isFirstLoyaltyCard = ((try? modelContext.fetchCount(FetchDescriptor<KBLoyaltyCard>(predicate: #Predicate<KBLoyaltyCard> {
            $0.familyId == familyId && $0.isDeleted == false
        }))) ?? 0) == 0

        let card = KBLoyaltyCard(
            familyId: familyId,
            brandId: brand?.id,
            brandName: resolvedBrandName,
            cardNumber: trimmedCardNumber,
            barcodeFormat: resolvedFormat,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryColorHex: resolvedPrimaryColor,
            secondaryColorHex: resolvedSecondaryColor,
            logoURL: resolvedLogoURL,
            visibilityScope: KBVisibilityScope.family,
            visibilityMemberIds: [],
            createdBy: uid,
            createdByName: displayName,
            updatedBy: uid,
            updatedByName: displayName,
            createdAt: .now,
            updatedAt: .now,
            isDeleted: false
        )
        card.syncState = .pendingUpsert

        modelContext.insert(card)
        do {
            try modelContext.save()
        } catch {
            let format = NSLocalizedString("Impossibile salvare la carta: %@", comment: "Loyalty card save error, %@ = underlying error description")
            errorMessage = String(format: format, error.localizedDescription)
            return
        }

        SyncCenter.shared.enqueueLoyaltyCardUpsert(
            cardId: card.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        AppAnalytics.contentCreated(type: "loyalty_card")
        if isFirstLoyaltyCard {
            AppAnalytics.featureFirstUse(feature: "loyalty_card")
        }

        onSaved(card.id)
    }
}
