//
//  AddLoyaltyCardBrandPickerView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Primo step del flusso "Aggiungi una carta": ricerca + sezione "Carte più
//  popolari" + lista alfabetica con indice laterale A-Z + CTA "Carta non in
//  elenco? Aggiungila manualmente".
//

import SwiftUI

struct AddLoyaltyCardBrandPickerView: View {
    let familyId: String
    /// Chiamato con l'id della carta salvata al termine del flusso.
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var selectedBrand: LoyaltyCardBrand?
    @State private var showManualEntry = false

    private var filteredBrands: [LoyaltyCardBrand] {
        LoyaltyCardCatalog.search(searchText)
    }

    private var groupedBrands: [(letter: String, brands: [LoyaltyCardBrand])] {
        LoyaltyCardCatalog.groupedByIndexLetter(filteredBrands)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    List {
                        if !isSearching {
                            let popular = LoyaltyCardCatalog.popular
                            if !popular.isEmpty {
                                Section("Carte più popolari") {
                                    ForEach(popular) { brand in
                                        brandRow(brand)
                                    }
                                }
                            }
                        }

                        ForEach(groupedBrands, id: \.letter) { group in
                            Section(group.letter) {
                                ForEach(group.brands) { brand in
                                    brandRow(brand)
                                }
                            }
                            .id(group.letter)
                        }

                        Section {
                            Button {
                                showManualEntry = true
                            } label: {
                                Label("Carta non in elenco? Aggiungila manualmente", systemImage: "plus.circle")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Cerca un negozio")

                    if !isSearching && groupedBrands.count > 3 {
                        indexBar(proxy: proxy)
                    }
                }
            }
            .navigationTitle("Scegli il negozio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .navigationDestination(item: $selectedBrand) { brand in
                LoyaltyCardScanEntryView(
                    familyId: familyId,
                    brand: brand
                ) { cardId in
                    onSaved(cardId)
                }
            }
            .sheet(isPresented: $showManualEntry) {
                LoyaltyCardManualBrandView(familyId: familyId) { cardId in
                    showManualEntry = false
                    onSaved(cardId)
                }
            }
        }
    }

    private func brandRow(_ brand: LoyaltyCardBrand) -> some View {
        Button {
            selectedBrand = brand
        } label: {
            HStack(spacing: 12) {
                // Logo reale del brand; se manca o non carica resta il
                // riquadro col gradiente del brand, come prima dei loghi.
                LoyaltyCardLogoView(brand: brand, style: .badge, size: 36)
                Text(brand.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func indexBar(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 2) {
            ForEach(groupedBrands.map(\.letter), id: \.self) { letter in
                Button {
                    withAnimation { proxy.scrollTo(letter, anchor: .top) }
                } label: {
                    Text(letter)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KBTheme.tint)
                }
            }
        }
        .padding(.trailing, 4)
    }
}

/// Step intermedio: propone scan o inserimento manuale del numero carta per
/// il brand selezionato dal catalogo.
private struct LoyaltyCardScanEntryView: View {
    let familyId: String
    let brand: LoyaltyCardBrand?
    let onSaved: (String) -> Void

    var body: some View {
        LoyaltyCardBarcodeScannerView(
            expectedFormat: brand?.defaultBarcodeFormat
        ) { text, format in
            proceedToForm(prefilledNumber: text, prefilledFormat: format)
        } onManualFallback: {
            proceedToForm(prefilledNumber: nil, prefilledFormat: nil)
        }
        .navigationTitle(brand?.name ?? NSLocalizedString("Carta", comment: "Fallback nav title when no loyalty card brand is set yet"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToForm) {
            LoyaltyCardFormView(
                familyId: familyId,
                brand: brand,
                prefilledCardNumber: pendingNumber,
                prefilledBarcodeFormat: pendingFormat
            ) { cardId in
                onSaved(cardId)
            }
        }
    }

    @State private var navigateToForm = false
    @State private var pendingNumber: String?
    @State private var pendingFormat: String?

    private func proceedToForm(prefilledNumber: String?, prefilledFormat: String?) {
        pendingNumber = prefilledNumber
        pendingFormat = prefilledFormat
        navigateToForm = true
    }
}

/// Flusso "carta non in elenco": nome negozio + colore scelti dall'utente.
private struct LoyaltyCardManualBrandView: View {
    let familyId: String
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoyaltyCardFormView(
                familyId: familyId,
                brand: nil,
                prefilledCardNumber: nil,
                prefilledBarcodeFormat: nil
            ) { cardId in
                onSaved(cardId)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }
}
