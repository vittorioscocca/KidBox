//
//  ShoppingTripsListView.swift
//  KidBox
//
//  Lo storico delle spese fatte, con il dettaglio dello scontrino.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct ShoppingTripsListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query private var trips: [KBShoppingTrip]

    private let familyId: String

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _trips = Query(
            filter: #Predicate<KBShoppingTrip> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBShoppingTrip.date, order: .reverse)]
        )
    }

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
        NavigationStack {
            Group {
                if trips.isEmpty {
                    // Stato vuoto senza azione: da qui non si crea uno
                    // scontrino, nasce dai prodotti spuntati nella lista.
                    VStack(spacing: 12) {
                        Image(systemName: "receipt")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Nessuna spesa salvata")
                            .font(.headline)
                        Text("Quando spunti i prodotti e tocchi «Salva spesa», lo scontrino finisce qui: negozio, totale e cosa avevi preso.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink {
                                ShoppingTripDetailView(trip: trip)
                            } label: {
                                row(trip)
                            }
                            .listRowBackground(cardBackground)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(trip)
                                } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(backgroundColor)
            .navigationTitle("Spese salvate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    private func row(_ trip: KBShoppingTrip) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 40, height: 40)
                .background(Color.green.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.storeName?.trimmedNonEmptyOrNil ?? String(localized: "Spesa"))
                    .font(.system(size: 17, weight: .semibold))
                Text(trip.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(trip.total.formatted(.currency(code: "EUR")))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func delete(_ trip: KBShoppingTrip) {
        // Lo scontrino sparisce, la spesa collegata no: i soldi sono usciti
        // comunque, e cancellarli da qui sarebbe una sorpresa nei conti.
        let uid = Auth.auth().currentUser?.uid ?? "local"
        trip.isDeleted = true
        trip.updatedBy = uid
        trip.updatedAt = Date()
        trip.syncState = .pendingDelete
        SyncCenter.shared.enqueueShoppingTripDelete(tripId: trip.id, familyId: familyId, modelContext: modelContext)
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}

// MARK: - Dettaglio

struct ShoppingTripDetailView: View {

    let trip: KBShoppingTrip
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Negozio", value: trip.storeName?.trimmedNonEmptyOrNil ?? String(localized: "Non indicato"))
                LabeledContent("Data", value: trip.date.formatted(date: .long, time: .omitted))
                LabeledContent("Totale", value: trip.total.formatted(.currency(code: "EUR")))
            }

            Section("Prodotti (\(trip.lines.count))") {
                if trip.lines.isEmpty {
                    Text("Nessun prodotto registrato")
                        .foregroundStyle(.secondary)
                } else {
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
            }

            if trip.linkedExpenseId != nil {
                Section {
                    Label("Registrata anche nelle Spese", systemImage: "eurosign.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle(trip.storeName?.trimmedNonEmptyOrNil ?? String(localized: "Spesa"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var trimmedNonEmptyOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
