//
//  HousePaymentDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct HousePaymentDetailView: View {
    let familyId: String
    let paymentId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var payments: [KBHousePayment]

    @State private var showEdit = false
    @State private var showDelete = false

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

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var payment: KBHousePayment? { payments.first }

    init(familyId: String, paymentId: String) {
        self.familyId = familyId
        self.paymentId = paymentId
        let fid = familyId
        let pid = paymentId
        _payments = Query(filter: #Predicate<KBHousePayment> { $0.id == pid && $0.familyId == fid })
    }

    var body: some View {
        Group {
            if let p = payment {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(p)
                        Text("Scadenze")
                            .font(.custom("Nunito", size: 13).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        if p.giornoDiScadenzaMensile != nil {
                            deadlineRow("Prossima scadenza mensile", p.nextMonthlyDeadlineDisplay())
                        }
                        if p.dataScadenza != nil {
                            deadlineRow("Prossima scadenza annuale", p.nextAnnualDeadlineDisplay())
                        }
                        if p.dataScadenzaContratto != nil {
                            deadlineRow("Scadenza contratto", p.dataScadenzaContratto)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("Voce non trovata", systemImage: "eurosign.circle")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(payment?.name ?? "Dettaglio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if payment != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let p = payment {
                HousePaymentFormView(familyId: familyId, existing: p)
            }
        }
        .alert("Eliminare questa voce?", isPresented: $showDelete) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) { deletePayment() }
        } message: {
            Text("Verrà rimossa per tutta la famiglia.")
        }
        .onAppear {
            SyncCenter.shared.startHousePaymentsRealtime(familyId: familyId, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func header(_ p: KBHousePayment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(accentOrange)
                Text(p.name)
                    .font(.custom("Nunito", size: 22).weight(.bold))
            }
            Text(KidBoxHousePaymentType(rawValue: p.typeRaw)?.title ?? p.typeRaw)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let st = p.subtypeRaw, !st.isEmpty {
                line("Tipo", st)
            }
            if let imp = p.importo {
                line("Importo", Self.formatEuro(imp))
            }
            if let f = p.fornitore, !f.isEmpty { line("Fornitore / Banca", f) }
            if let n = p.note, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(n)
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.custom("Nunito", size: 15))
        }
    }

    @ViewBuilder
    private func deadlineRow(_ title: String, _ date: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let d = date {
                    Text(HousePaymentDetailView.df.string(from: d))
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                    if let days = KidBoxUrgency.daysRemaining(to: d) {
                        Text(KidBoxUrgency.label(days: days))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(KidBoxUrgency.color(days: days))
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let d = date {
                Circle()
                    .fill(KidBoxUrgency.color(days: KidBoxUrgency.daysRemaining(to: d)))
                    .frame(width: 10, height: 10)
            }
        }
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        return f
    }()

    private static func formatEuro(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "it_IT")
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private func deletePayment() {
        guard let p = payment else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        Task { await HousePaymentReminderService.shared.cancelAll(paymentId: p.id) }
        p.isDeleted = true
        p.updatedAt = Date()
        p.updatedBy = uid
        p.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueHousePaymentDelete(paymentId: p.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.path.removeLast()
    }
}
