//
//  StorageUsageView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseFunctions
import StoreKit

struct StorageUsageView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager
    
    @StateObject private var vm = StorageUsageViewModel()
    @Query private var families: [KBFamily]
    
    @State private var showUpgradeSheet           = false
    @State private var showManageSubscriptions  = false
    @State private var showOfferCodeRedemption  = false
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    // MARK: - Dynamic theme
    
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
    
    private var familyId: String {
        if let fid = coordinator.activeFamilyId, !fid.isEmpty { return fid }
        return families.first?.id ?? ""
    }
    
    // MARK: - Body
    
    var body: some View {
        List {
            
            // ── Quota card ──────────────────────────────────────────────────
            Section {
                quotaCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .id(subscriptionManager.currentPlan) // forza rebuild SwiftUI al cambio piano
            }
            
            // ── Banner warning storage ──────────────────────────────────────
            if vm.isOverLimit || vm.isNearLimit {
                Section {
                    upgradeBanner
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            
            // ── Banner abbonamento in scadenza ──────────────────────────────
            if subscriptionManager.isCancelledButActive,
               let expiry = subscriptionManager.subscriptionExpirationDate {
                Section {
                    expiringBanner(expirationDate: expiry)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            
            // ── Sezioni ─────────────────────────────────────────────────────
            if !vm.isLoading && !vm.sections.isEmpty {
                Section("Utilizzo per sezione") {
                    ForEach(vm.sections) { section in
                        SectionRow(section: section,
                                   totalBytes: subscriptionManager.currentPlan.storageQuota)
                        .listRowBackground(cardBackground)
                    }
                }
            }
            
            // ── Piani disponibili ───────────────────────────────────────────
            Section("Piani disponibili") {
                ForEach(KBPlan.allCases, id: \.rawValue) { plan in
                    planRow(plan: plan)
                        .listRowBackground(cardBackground)
                }
            }
            
            // ── Gestione abbonamento ─────────────────────────────────────────
            if subscriptionManager.currentPlan != .free {
                Section("Abbonamento attivo") {
                    Button {
                        showManageSubscriptions = true
                    } label: {
                        HStack {
                            Label("Gestisci abbonamento", systemImage: "creditcard")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(cardBackground)
                    
                    if let expiry = subscriptionManager.subscriptionExpirationDate {
                        SubscriptionExpiryRow(
                            expirationDate: expiry,
                            willRenew: subscriptionManager.subscriptionWillRenew
                        )
                        .listRowBackground(cardBackground)
                    }
                }
            }
            
            // ── Footer actions ───────────────────────────────────────────────
            Section {
                // Info condivisione spazio
                Label {
                    Text("Lo spazio è condiviso tra tutti i membri della famiglia.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(tint)
                }
                .listRowBackground(cardBackground)
                
                // Ripristina acquisti
                Button {
                    Task { await subscriptionManager.restorePurchases() }
                } label: {
                    Label {
                        Text("Ripristina acquisti")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(tint)
                    }
                }
                .listRowBackground(cardBackground)
                
                if subscriptionManager.isFamilyOwner {
                    Button {
                        showOfferCodeRedemption = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Riscatta codice offerta")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("Codice promozionale o offerta App Store")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "giftcard.fill")
                                .foregroundStyle(tint)
                        }
                    }
                    .listRowBackground(cardBackground)
                }
            } footer: {
                Text("Gli acquisti vengono verificati tramite il tuo ID Apple. Il piano si applica all'intera famiglia. Per i codici offerta, Apple apre una schermata dedicata in cui inserire il codice.")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Utilizzo spazio")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            guard !familyId.isEmpty else { return }
            vm.load(modelContext: modelContext, familyId: familyId)
            Task {
                await subscriptionManager.loadPlan()
                await subscriptionManager.loadProducts()
            }
        }
        .onChange(of: familyId) { _, newId in
            guard !newId.isEmpty, vm.usedBytes == 0 else { return }
            vm.load(modelContext: modelContext, familyId: newId)
        }
        .onChange(of: subscriptionManager.currentPlan) { _, _ in
            guard !familyId.isEmpty else { return }
            vm.load(modelContext: modelContext, familyId: familyId)
        }
        .refreshable {
            guard !familyId.isEmpty else { return }
            let fid = familyId
            do {
                let functions = Functions.functions(region: "europe-west1")
                let result = try await functions.httpsCallable("initStorageUsage")
                    .call(["familyId": fid])
                print("✅ initStorageUsage:", result.data)
            } catch {
                print("❌ initStorageUsage error:", error)
            }
            vm.load(modelContext: modelContext, familyId: fid)
            await subscriptionManager.loadPlan()
        }
        // Apre lo sheet Apple di gestione abbonamenti.
        // Al dismiss (isShowing → false) eseguiamo più check con backoff progressivo:
        // StoreKit impiega alcuni secondi a propagare la cancellazione nel RenewalInfo.
        // @MainActor garantisce che i publish di @Published avvengano sul thread UI,
        // evitando che SwiftUI ignori o bufferizzi gli aggiornamenti.
        .offerCodeRedemption(isPresented: $showOfferCodeRedemption) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    await subscriptionManager.loadPlan()
                    await subscriptionManager.refreshCurrentEntitlement()
                case .failure:
                    break
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .onChange(of: showManageSubscriptions) { _, isShowing in
            guard !isShowing else { return }
            Task { @MainActor in
                await subscriptionManager.debugDumpAllTransactions()
                await subscriptionManager.refreshCurrentEntitlement()
                try? await Task.sleep(for: .seconds(3))
                await subscriptionManager.refreshCurrentEntitlement()
                try? await Task.sleep(for: .seconds(7))
                await subscriptionManager.refreshCurrentEntitlement()
            }
        }
        .alert("Errore acquisto", isPresented: .init(
            get: { subscriptionManager.purchaseError != nil },
            set: { if !$0 { subscriptionManager.clearPurchaseError() } }
        )) {
            Button("OK", role: .cancel) {
                subscriptionManager.clearPurchaseError()
            }
        } message: {
            Text(subscriptionManager.purchaseError ?? "")
        }
    }
    
    // MARK: - Quota card
    
    private var quotaCard: some View {
        let plan     = subscriptionManager.currentPlan
        let quota    = plan.storageQuota
        let fraction = Double(vm.usedBytes) / Double(quota)
        
        return VStack(alignment: .leading, spacing: 16) {
            
            HStack {
                Label("Spazio famiglia", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Piano \(plan.displayName) · \(plan.storageLabel)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(planColor(plan)))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(vm.usedBytes.formattedFileSize)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text("/ \(quota.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(min(fraction, 1.0) * 100))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(usedColor(fraction: fraction))
            }
            
            segmentedBar(fraction: min(fraction, 1.0), totalQuota: quota)
            
            HStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
                Text("\(max(0, quota - vm.usedBytes).formattedFileSize) disponibili per la famiglia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.07)
                      : Color.black.opacity(0.04))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Segmented bar
    
    private func segmentedBar(fraction: Double, totalQuota: Int64) -> some View {
        GeometryReader { geo in
            let totalWidth  = geo.size.width
            let usedWidth   = totalWidth * fraction
            let sectionsWithBytes = vm.sections.filter { $0.bytes > 0 }
            let sectionTotal = max(1, sectionsWithBytes.reduce(0) { $0 + $1.bytes })
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: totalWidth, height: 12)
                
                HStack(spacing: 1) {
                    ForEach(sectionsWithBytes) { s in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: s.color) ?? .accentColor)
                            .frame(
                                width: usedWidth * (Double(s.bytes) / Double(sectionTotal)),
                                height: 12
                            )
                    }
                }
                .frame(width: usedWidth, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: 12)
    }
    
    // MARK: - Plan row
    
    @ViewBuilder
    private func planRow(plan: KBPlan) -> some View {
        let isCurrent = subscriptionManager.currentPlan == plan
        let product   = subscriptionManager.storeProduct(for: plan)
        
        let nonOwnerPaidRow = !subscriptionManager.isFamilyOwner && !isCurrent && product != nil
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.displayName).font(.subheadline.bold())
                        if isCurrent {
                            Text("Piano attuale")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(tint))
                        } else if !plan.badge.isEmpty {
                            Text(plan.badge)
                                .font(.caption2.bold())
                                .foregroundStyle(planColor(plan))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(planColor(plan).opacity(0.12)))
                        }
                    }
                    HStack(spacing: 8) {
                        Label(plan.storageLabel + " storage", systemImage: "internaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                        if plan.includesAI {
                            Label("\(plan.aiDailyLimit) msg AI/giorno", systemImage: "sparkles")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label("Senza AI", systemImage: "sparkles")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer(minLength: 8)
                
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(planColor(plan))
                        .font(.title3)
                } else if let product {
                    if subscriptionManager.isFamilyOwner {
                        Button {
                            Task { await subscriptionManager.purchase(plan) }
                        } label: {
                            if subscriptionManager.isPurchasing {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(product.displayPrice + "/mese")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(planColor(plan)))
                            }
                        }
                        .disabled(subscriptionManager.isPurchasing)
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(plan.monthlyPrice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if nonOwnerPaidRow {
                NonOwnerUpgradeNotice()
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Expiring banner (abbonamento cancellato ma attivo)
    
    private func expiringBanner(expirationDate: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale    = Locale(identifier: "it_IT")
        let dateStr = formatter.string(from: expirationDate)
        
        return HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Abbonamento in scadenza")
                    .font(.subheadline.bold())
                Text("Il tuo piano \(subscriptionManager.currentPlan.displayName) scade il \(dateStr). Dopo quella data tornerai al piano Free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Rinnova") {
                showManageSubscriptions = true
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.orange))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.08))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Upgrade banner
    
    private var upgradeBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: vm.isOverLimit ? "exclamationmark.triangle.fill" : "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(vm.isOverLimit ? .red : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.isOverLimit ? "Spazio esaurito" : "Spazio quasi esaurito")
                        .font(.subheadline.bold())
                    Text(vm.isOverLimit
                         ? "Gli upload sono bloccati. Passa a Pro per 5 GB."
                         : "Hai usato l'80% dello spazio. Passa a Pro per continuare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if subscriptionManager.isFamilyOwner {
                    Button("Upgrade") {
                        Task { await subscriptionManager.purchase(.pro) }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(vm.isOverLimit ? Color.red : Color.orange))
                    .disabled(subscriptionManager.isPurchasing)
                }
            }
            
            if !subscriptionManager.isFamilyOwner {
                NonOwnerUpgradeNotice()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(vm.isOverLimit
                      ? Color.red.opacity(0.08)
                      : Color.orange.opacity(0.08))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Helpers
    
    private func usedColor(fraction: Double) -> Color {
        switch fraction {
        case ..<0.6:  return .green
        case ..<0.85: return .orange
        default:      return .red
        }
    }
    
    private func planColor(_ plan: KBPlan) -> Color {
        switch plan {
        case .free: return .gray
        case .pro:  return tint
        case .max:  return Color(red: 0.55, green: 0.35, blue: 0.9)
        }
    }
}

// MARK: - Subscription Expiry Row

struct SubscriptionExpiryRow: View {
    let expirationDate: Date
    let willRenew: Bool
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale    = Locale(identifier: "it_IT")
        return f
    }()
    
    var body: some View {
        HStack {
            Text(willRenew ? "Rinnovo automatico il" : "Scade il")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.formatter.string(from: expirationDate))
                .font(.caption.bold())
                .foregroundStyle(willRenew ? .secondary : Color.orange)
        }
    }
}

// MARK: - Section Row

private struct SectionRow: View {
    let section: KBStorageSection
    let totalBytes: Int64
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((Color(hex: section.color) ?? .accentColor).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: section.icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: section.color) ?? .accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(section.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if section.bytes > 0 {
                        Text(section.bytes.formattedFileSize)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(hex: section.color) ?? .accentColor)
                    } else {
                        Text("Nessun dato")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                let fraction = min(1.0, Double(section.bytes) / Double(max(1, totalBytes)))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                        if section.bytes > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: section.color) ?? .accentColor)
                                .frame(width: max(4, g.size.width * fraction))
                        }
                    }
                }
                .frame(height: 4)
                
                Text("\(section.recordCount) \(section.recordCount == 1 ? "elemento" : "elementi")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
