//
//  HomeItemsHomeView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct HomeItemsHomeView: View {
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var items: [KBHomeItem]
    @Query private var housePayments: [KBHousePayment]

    @State private var showAdd = false
    @State private var showAddPayment = false

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

    /// Card Casa (Scadenze & Pagamenti) in tema chiaro.
    private var paymentCardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.18)
            : (Color(hex: "#F2F0EB") ?? cardBackground)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }
    private var titleInk: Color {
        colorScheme == .dark ? .white : (Color(hex: "#1A1A1A") ?? .primary)
    }

    private var groupedPrefix: [(title: String, rows: [KBHomeItem])] {
        let order = ["appliance", "system", "contract"]
        let dict = Dictionary(grouping: items) { $0.categoryRaw }
        return order.compactMap { key in
            guard let rows = dict[key]?.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), !rows.isEmpty else { return nil }
            return (KidBoxHomeCategory.title(for: key), rows)
        }
    }

    private var otherHomeSection: (title: String, rows: [KBHomeItem])? {
        let dict = Dictionary(grouping: items) { $0.categoryRaw }
        guard let rows = dict["other"]?.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), !rows.isEmpty else { return nil }
        return (KidBoxHomeCategory.title(for: "other"), rows)
    }

    private var sortedHousePayments: [KBHousePayment] {
        func rank(for p: KBHousePayment) -> Int {
            guard let d = p.earliestDisplayDeadline(), let days = KidBoxUrgency.daysRemaining(to: d) else { return 3 }
            if days < 30 { return 0 }
            if days < 60 { return 1 }
            return 2
        }
        return housePayments.sorted { a, b in
            let ra = rank(for: a)
            let rb = rank(for: b)
            if ra != rb { return ra < rb }
            let da = a.earliestDisplayDeadline() ?? .distantFuture
            let db = b.earliestDisplayDeadline() ?? .distantFuture
            if da != db { return da < db }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _items = Query(
            filter: #Predicate<KBHomeItem> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBHomeItem.name, order: .forward)]
        )
        _housePayments = Query(
            filter: #Predicate<KBHousePayment> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBHousePayment.name, order: .forward)]
        )
    }

    var body: some View {
        Group {
            if items.isEmpty && housePayments.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedPrefix, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.rows, id: \.id) { row in
                                homeRow(row)
                                    .listRowBackground(cardBackground)
                            }
                        }
                    }
                    if !sortedHousePayments.isEmpty {
                        Section("Scadenze & Pagamenti") {
                            ForEach(sortedHousePayments, id: \.id) { pay in
                                housePaymentRow(pay)
                                    .listRowBackground(paymentCardBackground)
                            }
                        }
                    }
                    if let other = otherHomeSection {
                        Section(other.title) {
                            ForEach(other.rows, id: \.id) { row in
                                homeRow(row)
                                    .listRowBackground(cardBackground)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Casa")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Elemento casa") { showAdd = true }
                    Button("Scadenza o pagamento") { showAddPayment = true }
                } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .tint(accentOrange)
            }
        }
        .sheet(isPresented: $showAdd) {
            HomeItemFormView(familyId: familyId, existing: nil)
        }
        .sheet(isPresented: $showAddPayment) {
            HousePaymentFormView(familyId: familyId, existing: nil)
        }
        .onAppear {
            SyncCenter.shared.startHomeItemsRealtime(familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.startHousePaymentsRealtime(familyId: familyId, modelContext: modelContext)
        }
        .onDisappear {
            SyncCenter.shared.stopHomeItemsRealtime()
            SyncCenter.shared.stopHousePaymentsRealtime()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "#8B6914") ?? .brown)
            Text("Nessun elemento ancora")
                .font(.custom("Nunito", size: 18).weight(.semibold))
                .foregroundStyle(titleInk)
            VStack(spacing: 12) {
                Button { showAdd = true } label: {
                    Text("Aggiungi elemento")
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(accentOrange, in: Capsule())
                }
                .buttonStyle(.plain)
                Button { showAddPayment = true } label: {
                    Text("Aggiungi scadenza o pagamento")
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(accentOrange)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(paymentCardBackground, in: Capsule())
                        .overlay(Capsule().stroke(accentOrange, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func homeRow(_ it: KBHomeItem) -> some View {
        Button {
            coordinator.navigate(to: .homeItemDetail(familyId: familyId, itemId: it.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: KidBoxHomeCategory.symbol(for: it.categoryRaw))
                    .foregroundStyle(Color(hex: "#8B6914") ?? .brown)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(it.name)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(titleInk)
                    let bm = [it.brand, it.model].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
                    if !bm.isEmpty {
                        Text(bm)
                            .font(.custom("Nunito", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    if let badge = nextDeadlineBadge(it) {
                        Text(badge.text)
                            .font(.custom("Nunito", size: 12).weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badge.color, in: Capsule())
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func housePaymentRow(_ pay: KBHousePayment) -> some View {
        Button {
            coordinator.navigate(to: .housePaymentDetail(familyId: familyId, paymentId: pay.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(accentOrange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pay.name)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(titleInk)
                    if let st = pay.subtypeRaw, !st.isEmpty {
                        Text(st)
                            .font(.custom("Nunito", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    if let badge = housePaymentDeadlineBadge(pay) {
                        Text(badge.text)
                            .font(.custom("Nunito", size: 12).weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badge.color, in: Capsule())
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func housePaymentDeadlineBadge(_ pay: KBHousePayment) -> (text: String, color: Color)? {
        guard let d = pay.earliestDisplayDeadline() else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0
        let color: Color
        if days < 0 { color = .red }
        else if days < 30 { color = .red }
        else if days < 60 { color = Color(hex: "#FF9500") ?? .orange }
        else { color = .green }
        let df = HomeItemsHomeView.shortDF
        return ("Scadenza: \(df.string(from: d))", color)
    }

    private func nextDeadlineBadge(_ it: KBHomeItem) -> (text: String, color: Color)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var best: (Date, String)? = nil
        if let w = it.warrantyExpiryDate {
            best = (w, "Garanzia")
        }
        if let s = it.nextServiceDate {
            if let cur = best {
                if cal.startOfDay(for: s) < cal.startOfDay(for: cur.0) { best = (s, "Manutenzione") }
            } else {
                best = (s, "Manutenzione")
            }
        }
        guard let (d, label) = best else { return nil }
        let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0
        let color: Color
        if days < 0 { color = .red }
        else if days < 30 { color = .red }
        else if days < 60 { color = Color(hex: "#FF9500") ?? .orange }
        else { color = .green }
        let df = HomeItemsHomeView.shortDF
        return ("\(label): \(df.string(from: d))", color)
    }

    private static let shortDF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        return f
    }()
}

enum KidBoxHomeCategory {
    static func title(for raw: String) -> String {
        switch raw {
        case "appliance": return "Elettrodomestici"
        case "system": return "Impianti"
        case "contract": return "Contratti"
        default: return "Altro"
        }
    }

    static func symbol(for raw: String) -> String {
        switch raw {
        case "appliance": return "washer.fill"
        case "system": return "flame.fill"
        case "contract": return "doc.text.fill"
        default: return "square.grid.2x2"
        }
    }
}
