//
//  HomeItemDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct HomeItemDetailView: View {
    let familyId: String
    let itemId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var items: [KBHomeItem]

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

    private var item: KBHomeItem? { items.first }

    init(familyId: String, itemId: String) {
        self.familyId = familyId
        self.itemId = itemId
        let fid = familyId
        let iid = itemId
        _items = Query(filter: #Predicate<KBHomeItem> { $0.id == iid && $0.familyId == fid })
    }

    var body: some View {
        Group {
            if let it = item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(it)
                        Text("Scadenze")
                            .font(.custom("Nunito", size: 13).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        deadlineRow("Garanzia", it.warrantyExpiryDate)
                        deadlineRow("Prossima manutenzione", it.nextServiceDate)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("Elemento non trovato", systemImage: "house")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(item?.name ?? "Dettaglio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let it = item {
                HomeItemFormView(familyId: familyId, existing: it)
            }
        }
        .alert("Eliminare questo elemento?", isPresented: $showDelete) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) { deleteItem() }
        } message: {
            Text("Verrà rimosso per tutta la famiglia.")
        }
        .onAppear {
            SyncCenter.shared.startHomeItemsRealtime(familyId: familyId, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func header(_ it: KBHomeItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: KidBoxHomeCategory.symbol(for: it.categoryRaw))
                    .font(.title)
                    .foregroundStyle(Color(hex: "#8B6914") ?? .brown)
                Text(it.name)
                    .font(.custom("Nunito", size: 22).weight(.bold))
            }
            Text(KidBoxHomeCategory.title(for: it.categoryRaw))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let b = it.brand, !b.isEmpty { line("Marca", b) }
            if let m = it.model, !m.isEmpty { line("Modello", m) }
            if let s = it.serialNumber, !s.isEmpty { line("Serie", s) }
            if let p = it.purchaseDate { line("Acquisto", HomeItemDetailView.df.string(from: p)) }
            if let m = it.servicePeriodMonths {
                line("Periodicità", "\(m) mesi")
            }
            if let n = it.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    Text(HomeItemDetailView.df.string(from: d))
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

    private func deleteItem() {
        guard let it = item else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        it.isDeleted = true
        it.updatedAt = Date()
        it.updatedBy = uid
        it.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueHomeItemDelete(itemId: it.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.path.removeLast()
    }
}

enum KidBoxUrgency {
    static func daysRemaining(to date: Date) -> Int? {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day
    }

    static func color(days: Int?) -> Color {
        guard let d = days else { return .gray }
        if d < 0 { return .red }
        if d < 30 { return .red }
        if d < 60 { return Color(hex: "#FF9500") ?? .orange }
        return .green
    }

    static func label(days: Int?) -> String {
        guard let d = days else { return "" }
        if d < 0 { return "Scaduto" }
        return "Tra \(d) giorni"
    }
}
