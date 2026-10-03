//
//  PaymentCardFormView.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//
//  Inserimento e modifica di una carta di pagamento. Solo a mano: niente
//  lettura AI, niente scansione del numero. Il PIN si scrive in un campo
//  nascosto. I controlli (Luhn, IBAN, mese)
//  avvisano ma non bloccano, tranne il numero: almeno 12 cifre.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PaymentCardFormView: View {
    let familyId: String
    /// `nil` = nuova carta.
    let card: KBPaymentCard?
    let onSaved: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [KBFamilyMember]

    @State private var label = ""
    @State private var cardNumber = ""
    @State private var holderName = ""
    @State private var expiry = ""
    @State private var iban = ""
    @State private var notes = ""
    @State private var pin = ""
    @State private var colorHex = PaymentCardPalette.defaultHex
    @State private var visibilityScope = KBVisibilityScope.onlyCreator
    @State private var visibilityMemberIds: Set<String> = []
    @State private var isVisibilitySheetPresented = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    init(familyId: String, card: KBPaymentCard?, onSaved: @escaping (String) -> Void) {
        self.familyId = familyId
        self.card = card
        self.onSaved = onSaved
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var numberDigits: String { PaymentCardFormat.digits(cardNumber) }

    private var canSave: Bool { numberDigits.count >= 12 && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PaymentCardTileView(plain: preview, colorHex: colorHex, height: 190)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Nome della carta (opzionale)") {
                    TextField("Es. Visa di Marco", text: $label)
                }

                Section {
                    TextField("Numero carta", text: $cardNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.creditCardNumber)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: cardNumber) { _, new in
                            let formatted = PaymentCardFormat.grouped(new)
                            if formatted != new { cardNumber = formatted }
                        }
                } header: {
                    Text("Numero carta")
                } footer: {
                    if numberDigits.count >= 12, !PaymentCardFormat.passesLuhn(numberDigits) {
                        Text("Il numero non sembra valido: controlla le cifre.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Intestatario") {
                    TextField("Nome e cognome come sulla carta", text: $holderName)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.name)
                }

                Section {
                    TextField("MM/AA", text: $expiry)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: expiry) { _, new in
                            let formatted = PaymentCardFormat.expiryInput(new)
                            if formatted != new { expiry = formatted }
                        }
                } header: {
                    Text("Scadenza")
                } footer: {
                    if expiry.count == 5, !PaymentCardFormat.isValidExpiry(expiry) {
                        Text("Il mese deve essere fra 01 e 12.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("IT00 X000 0000 0000 0000 0000 000", text: $iban)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: iban) { _, new in
                            let formatted = PaymentCardFormat.ibanGrouped(new)
                            if formatted != new { iban = formatted }
                        }
                } header: {
                    Text("IBAN (opzionale)")
                } footer: {
                    if PaymentCardFormat.ibanCompact(iban).count >= 15, !PaymentCardFormat.isValidIBAN(iban) {
                        Text("L'IBAN non sembra valido: controlla i caratteri.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: pin) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(8))
                            if digits != new { pin = digits }
                        }
                } header: {
                    Text("PIN (opzionale)")
                } footer: {
                    Text("Il PIN non compare mai sulla carta: per vederlo o copiarlo serve Face ID o il codice del telefono.")
                }

                Section("Colore") {
                    colorSwatches
                }

                Section("Visibilità") {
                    Button {
                        isVisibilitySheetPresented = true
                    } label: {
                        HStack {
                            Text(KBVisibilityScope.chipLabel(for: visibilityScope))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    TextField("Nota (opzionale)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("Non salvare il CVV: KidBox non lo chiede. Numero, intestatario, scadenza, IBAN, PIN e foto sono cifrati sul telefono prima di partire e l'AI non li legge.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(card == nil ? Text("Nuova carta") : Text("Modifica carta"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("Salva") }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isVisibilitySheetPresented) {
                VisibilityPickerSheet(
                    selectedScope: $visibilityScope,
                    selectedMemberIds: $visibilityMemberIds,
                    members: members.filter { $0.userId != currentUid },
                    currentUid: currentUid,
                    scopeSectionTitle: "Chi può vedere questa carta"
                ) { scope, memberIds in
                    visibilityScope = scope
                    visibilityMemberIds = memberIds
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var preview: PaymentCardPlain {
        var p = PaymentCardPlain()
        p.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        p.cardNumber = numberDigits
        p.holderName = holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        p.expiry = expiry
        return p
    }

    private var colorSwatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PaymentCardPalette.all, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color.loyaltyCardColor(hex: hex))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if hex == colorHex {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Caricamento / salvataggio

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        guard let card else { return }
        let plain = PaymentCardPlain(card: card, userId: currentUid)
        label = plain.label
        cardNumber = PaymentCardFormat.grouped(plain.cardNumber)
        holderName = plain.holderName
        expiry = plain.expiry
        iban = PaymentCardFormat.ibanGrouped(plain.iban)
        notes = plain.notes
        pin = plain.pin
        colorHex = card.colorHex
        visibilityScope = KBPaymentCard.normalizedVisibilityScope(card.visibilityScope)
        visibilityMemberIds = Set(card.visibilityMemberIds ?? [])
    }

    private func save() {
        guard canSave, let uid = currentUid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let displayName = Auth.auth().currentUser?.displayName ?? ""
        let isNew = card == nil
        let isFirst = isNew && ((try? modelContext.fetchCount(FetchDescriptor<KBPaymentCard>(predicate: #Predicate<KBPaymentCard> {
            $0.familyId == familyId && $0.isDeleted == false
        }))) ?? 0) == 0

        let target = card ?? KBPaymentCard(
            familyId: familyId,
            createdBy: uid,
            createdByName: displayName,
            updatedBy: uid,
            updatedByName: displayName
        )

        var plain = PaymentCardPlain()
        plain.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        plain.cardNumber = numberDigits
        plain.holderName = holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        plain.expiry = PaymentCardFormat.isValidExpiry(expiry) ? expiry : ""
        plain.iban = PaymentCardFormat.ibanCompact(iban)
        plain.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plain.pin = pin

        do {
            try plain.seal(into: target, userId: uid)
        } catch {
            // Senza chiave di famiglia non si salva niente in chiaro.
            errorMessage = NSLocalizedString("Impossibile cifrare la carta: la chiave della famiglia non è disponibile su questo dispositivo.", comment: "Payment card save error: missing family key")
            return
        }

        target.colorHex = colorHex
        target.visibilityScope = KBPaymentCard.normalizedVisibilityScope(visibilityScope)
        target.visibilityMemberIds = visibilityScope == KBVisibilityScope.members ? Array(visibilityMemberIds) : []
        target.updatedBy = uid
        target.updatedByName = displayName
        target.updatedAt = .now
        target.syncState = .pendingUpsert

        if isNew { modelContext.insert(target) }
        do {
            try modelContext.save()
        } catch {
            let format = NSLocalizedString("Impossibile salvare la carta: %@", comment: "Loyalty card save error, %@ = underlying error description")
            errorMessage = String(format: format, error.localizedDescription)
            return
        }

        SyncCenter.shared.enqueuePaymentCardUpsert(cardId: target.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        if isNew {
            AppAnalytics.contentCreated(type: "payment_card")
            if isFirst { AppAnalytics.featureFirstUse(feature: "payment_card") }
        }

        onSaved(target.id)
        if !isNew { dismiss() }
    }
}
