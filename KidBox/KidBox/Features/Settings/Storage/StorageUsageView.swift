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
    
    @State private var showUpgradeSheet = false
    
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
            }
            
            // ── Banner warning ──────────────────────────────────────────────
            if vm.isOverLimit || vm.isNearLimit {
                Section {
                    upgradeBanner
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
            
            // ── Note ────────────────────────────────────────────────────────
            Section {
                Text("Lo spazio è condiviso da tutti i membri della famiglia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                
                Button("Ripristina acquisti") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            
            // ── Init storage (debug/admin) ───────────────────────────────────
            Section {
                Button("Ricalcola storage") {
                    let fid = familyId
                    Task {
                        do {
                            let functions = Functions.functions(region: "europe-west1")
                            let result = try await functions.httpsCallable("initStorageUsage")
                                .call(["familyId": fid])
                            print("✅ initStorageUsage:", result.data)
                            vm.load(modelContext: modelContext, familyId: fid)
                        } catch {
                            print("❌ initStorageUsage error:", error)
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(cardBackground)
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
        .refreshable {
            guard !familyId.isEmpty else { return }
            vm.load(modelContext: modelContext, familyId: familyId)
            await subscriptionManager.loadPlan()
        }
        .alert("Errore acquisto", isPresented: .init(
            get: { subscriptionManager.purchaseError != nil },
            set: { if !$0 { } }
        )) {
            Button("OK", role: .cancel) { }
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
            
            Spacer()
            
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(planColor(plan))
                    .font(.title3)
            } else if let product {
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
            } else {
                Text(plan.monthlyPrice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Upgrade banner
    
    private var upgradeBanner: some View {
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
