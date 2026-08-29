//
//  SaveShoppingTripView.swift
//  KidBox
//
//  "Salva spesa": archivia quello che è stato preso come uno scontrino, e ne
//  crea la spesa corrispondente nella sezione Spese.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct SaveShoppingTripView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let familyId: String
    /// I prodotti spuntati, così com'erano al momento del tocco.
    let purchasedItems: [KBGroceryItem]
    /// Chiamata a salvataggio riuscito: la lista svuota i prodotti archiviati.
    let onSaved: () -> Void

    @State private var storeName: String = ""
    @State private var totalText: String = ""
    @State private var date: Date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var total: Double? {
        let cleaned = totalText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Negozio") {
                    TextField("Es. Conad, Esselunga…", text: $storeName)
                        .autocorrectionDisabled()
                }

                Section("Totale") {
                    HStack {
                        TextField("0,00", text: $totalText)
                            .keyboardType(.decimalPad)
                        Text("€").foregroundStyle(.secondary)
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }

                Section {
                    ForEach(purchasedItems) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            if let quantity = item.quantity, quantity > 1 {
                                Text("x \(quantity)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Prodotti presi (\(purchasedItems.count))")
                } footer: {
                    // Detto prima di salvare, non scoperto dopo.
                    Text("Salvando, questi prodotti escono dalla lista e restano nello storico. Viene creata anche una spesa nella sezione Spese.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle("Salva spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { Task { await save() } }
                        .bold()
                        .disabled(total == nil || purchasedItems.isEmpty || isSaving)
                }
            }
        }
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        guard let total, !purchasedItems.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let store = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = purchasedItems.map {
            KBShoppingTripLine(name: $0.name, quantity: $0.quantity)
        }
        // L'elenco finisce anche nelle note della spesa: chi apre la sezione
        // Spese vede cosa c'era dentro senza tornare qui.
        let notes = lines
            .map { line in
                (line.quantity ?? 1) > 1 ? "\(line.name) x\(line.quantity ?? 1)" : line.name
            }
            .joined(separator: ", ")

        let trip = KBShoppingTrip(
            familyId: familyId,
            storeName: store.isEmpty ? nil : store,
            total: total,
            date: date,
            lines: lines,
            notes: notes.isEmpty ? nil : notes,
            createdAt: now,
            updatedAt: now,
            updatedBy: uid,
            createdBy: uid
        )

        // La categoria "Spesa" deve esistere prima di agganciarcisi: su una
        // famiglia che non ha mai aperto le Spese non è ancora stata creata.
        KBExpenseCategory.seedDefaults(familyId: familyId, context: modelContext)

        // La spesa nella sezione Spese è la voce che conta i soldi; lo scontrino
        // qui è il dettaglio. `linkedExpenseId` tiene insieme i due.
        let expense = KBExpense(
            familyId: familyId,
            title: store.isEmpty ? String(localized: "Spesa") : store,
            amount: total,
            date: date,
            categoryId: KBExpenseCategory.defaultCategoryId(familyId: familyId, slug: "spesa"),
            notes: notes.isEmpty ? nil : notes,
            attachedDocumentId: nil,
            createdByUid: uid
        )
        trip.linkedExpenseId = expense.id

        modelContext.insert(expense)
        modelContext.insert(trip)

        trip.syncState = .pendingUpsert
        expense.syncState = .pendingUpsert

        // I prodotti archiviati escono dalla lista: lo scontrino li conserva.
        for item in purchasedItems {
            item.isDeleted = true
            item.updatedBy = uid
            item.updatedAt = now
            item.syncState = .pendingDelete
            item.lastSyncError = nil
            SyncCenter.shared.enqueueGroceryDelete(itemId: item.id, familyId: familyId, modelContext: modelContext)
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        SyncCenter.shared.enqueueShoppingTripUpsert(tripId: trip.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.enqueueExpenseUpsert(expenseId: expense.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        await SyncCenter.shared.flushGrocery(modelContext: modelContext)

        AppAnalytics.contentCreated(type: "expenses")

        onSaved()
        dismiss()
    }
}
