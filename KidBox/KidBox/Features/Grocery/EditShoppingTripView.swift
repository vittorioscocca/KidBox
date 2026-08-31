//
//  EditShoppingTripView.swift
//  KidBox
//
//  Modifica di uno scontrino già salvato.
//
//  Scontrino e spesa sono due facce dello stesso fatto: quello che si cambia
//  qui si riflette sulla `KBExpense` collegata da `linkedExpenseId`, altrimenti
//  ci si ritrova uno scontrino da 52 € accanto a una spesa da 45 €.
//
//  Il totale governa l'esistenza della spesa: toglierlo la elimina, aggiungerlo
//  a uno scontrino che non ce l'aveva la crea.
//
//  I prodotti non si toccano: sono l'archivio di cosa è stato preso davvero, e
//  riscriverli a posteriori vorrebbe dire falsificare lo scontrino.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct EditShoppingTripView: View {

    let trip: KBShoppingTrip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var storeName: String = ""
    @State private var totalText: String = ""
    @State private var date: Date = Date()
    @State private var isSaving = false

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    /// `nil` quando il campo è vuoto o illeggibile: è il caso «senza importo»,
    /// non un errore da bloccare.
    private var total: Double? {
        let cleaned = totalText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Negozio") {
                    TextField("Es. Conad, Esselunga…", text: $storeName)
                }

                Section("Totale") {
                    TextField("0,00", text: $totalText)
                        .keyboardType(.decimalPad)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }

                Section("Prodotti (\(trip.lines.count))") {
                    ForEach(trip.lines) { line in
                        HStack {
                            Text(line.name)
                            Spacer()
                            if let quantity = line.quantity, quantity > 1 {
                                Text("x \(quantity)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    Text("Cambiando il totale si aggiorna anche la spesa in Spese; togliendolo, la spesa viene eliminata.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle("Modifica spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                storeName = trip.storeName ?? ""
                totalText = trip.total > 0 ? String(format: "%.2f", trip.total) : ""
                date = trip.date
            }
        }
    }

    // MARK: - Salvataggio

    private func save() {
        isSaving = true
        defer { isSaving = false }

        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let store = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let familyId = trip.familyId

        trip.storeName = store.isEmpty ? nil : store
        trip.total = total ?? 0
        trip.date = date
        trip.updatedAt = now
        trip.updatedBy = uid

        syncLinkedExpense(familyId: familyId, store: store, uid: uid, now: now)

        trip.syncState = .pendingUpsert
        SyncCenter.shared.enqueueShoppingTripUpsert(tripId: trip.id, familyId: familyId, modelContext: modelContext)
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }

    /// Allinea la spesa collegata: la aggiorna, la crea o la elimina a seconda
    /// che un totale ci sia o no.
    private func syncLinkedExpense(familyId: String, store: String, uid: String, now: Date) {
        let existing = linkedExpense(familyId: familyId)

        guard let amount = total, amount > 0 else {
            // Totale tolto: la spesa non ha più ragione di stare nei conti.
            if let existing {
                existing.isDeleted = true
                existing.updatedAt = now
                existing.updatedBy = uid
                SyncCenter.shared.enqueueExpenseDelete(expenseId: existing.id, familyId: familyId, modelContext: modelContext)
            }
            trip.linkedExpenseId = nil
            return
        }

        let title = store.isEmpty ? String(localized: "Spesa") : store

        if let existing {
            existing.title = title
            existing.amount = amount
            existing.date = date
            existing.isDeleted = false
            existing.updatedAt = now
            existing.updatedBy = uid
            SyncCenter.shared.enqueueExpenseUpsert(expenseId: existing.id, familyId: familyId, modelContext: modelContext)
            return
        }

        // Scontrino salvato senza importo: la spesa nasce adesso.
        KBExpenseCategory.seedDefaults(familyId: familyId, context: modelContext)
        let expense = KBExpense(
            familyId: familyId,
            title: title,
            amount: amount,
            date: date,
            categoryId: KBExpenseCategory.defaultCategoryId(familyId: familyId, slug: "spesa"),
            notes: trip.notes,
            attachedDocumentId: nil,
            createdByUid: uid
        )
        modelContext.insert(expense)
        expense.syncState = .pendingUpsert
        trip.linkedExpenseId = expense.id
        SyncCenter.shared.enqueueExpenseUpsert(expenseId: expense.id, familyId: familyId, modelContext: modelContext)
    }

    private func linkedExpense(familyId: String) -> KBExpense? {
        guard let expenseId = trip.linkedExpenseId, !expenseId.isEmpty else { return nil }
        let descriptor = FetchDescriptor<KBExpense>(
            predicate: #Predicate<KBExpense> { $0.id == expenseId && $0.familyId == familyId }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
