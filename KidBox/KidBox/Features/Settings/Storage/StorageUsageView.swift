//
//  StorageUsageView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseFunctions

struct StorageUsageView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @StateObject private var vm = StorageUsageViewModel()
    @Query private var families: [KBFamily]
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    // Recupera familyId: prima dal coordinator, fallback da SwiftData locale.
    // Funziona anche sul simulatore al primo lancio quando activeFamilyId è ancora nil.
    private var familyId: String {
        if let fid = coordinator.activeFamilyId, !fid.isEmpty { return fid }
        return families.first?.id ?? ""
    }
    
    var body: some View {
        List {
            Section {
                quotaCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            if vm.isOverLimit || vm.isNearLimit {
                Section {
                    upgradeBanner
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            
            if !vm.isLoading && !vm.sections.isEmpty {
                Section("Utilizzo per sezione") {
                    ForEach(vm.sections) { section in
                        SectionRow(section: section, totalBytes: StorageUsageViewModel.totalQuotaBytes)
                    }
                }
            }
            
            Section("Piani disponibili") {
                planRow(name: "Free",  quota: StorageUsageViewModel.quotaFree,  price: "Gratis",     isCurrent: true)
                planRow(name: "Pro",   quota: StorageUsageViewModel.quotaPro,   price: "€4,99/mese", isCurrent: false)
                planRow(name: "Max",   quota: StorageUsageViewModel.quotaMax,   price: "€9,99/mese", isCurrent: false)
            }
            
            Section {
                Text("Lo spazio è condiviso da tutti i membri della famiglia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            Button("Init Storage") {
                let fid = familyId
                Task {
                    do {
                        let functions = Functions.functions(region: "europe-west1")
                        let result = try await functions.httpsCallable("initStorageUsage")
                            .call(["familyId": fid])
                        print("✅ result:", result.data)
                        vm.load(modelContext: modelContext, familyId: fid)
                    } catch {
                        print("❌ error:", error)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Utilizzo spazio")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            guard !familyId.isEmpty else { return }
            vm.load(modelContext: modelContext, familyId: familyId)
        }
        .onChange(of: familyId) { _, newId in
            guard !newId.isEmpty, vm.usedBytes == 0 else { return }
            vm.load(modelContext: modelContext, familyId: newId)
        }
        .refreshable {
            guard !familyId.isEmpty else { return }
            vm.load(modelContext: modelContext, familyId: familyId)
        }
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
            
            Button("Upgrade") { }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(vm.isOverLimit ? Color.red : Color.orange))
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
    
    // MARK: - Plan row
    
    private func planRow(name: String, quota: Int64, price: String, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.subheadline.bold())
                    if isCurrent {
                        Text("Piano attuale")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(tint))
                    }
                }
                Text(quota.formattedFileSize + " storage")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(price)
                .font(.subheadline)
                .foregroundStyle(isCurrent ? .secondary : tint)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Quota card
    
    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack {
                Label("Spazio famiglia", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Piano Free · 200 MB")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(tint))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(vm.usedBytes.formattedFileSize)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text("/ \(StorageUsageViewModel.totalQuotaBytes.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(vm.usedFraction * 100))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(usedColor)
            }
            
            segmentedBar
            
            HStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
                Text("\(vm.freeBytes.formattedFileSize) disponibili per la famiglia")
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
    
    private var segmentedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                let sectionsWithBytes = vm.sections.filter { $0.bytes > 0 }
                ForEach(sectionsWithBytes) { s in
                    let fraction = Double(s.bytes) / Double(StorageUsageViewModel.totalQuotaBytes)
                    let w = max(4, geo.size.width * fraction)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: s.color) ?? .accentColor)
                        .frame(width: w, height: 12)
                }
                Spacer(minLength: 0)
                    .frame(
                        width: max(0, geo.size.width * (1.0 - vm.usedFraction) - 2),
                        height: 12
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
        }
        .frame(height: 12)
    }
    
    private var usedColor: Color {
        switch vm.usedFraction {
        case ..<0.6:  return .green
        case ..<0.85: return .orange
        default:      return .red
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
                    Text(section.bytes.formattedFileSize)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: section.color) ?? .accentColor)
                }
                
                let fraction = min(1.0, Double(section.bytes) / Double(totalBytes))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: section.color) ?? .accentColor)
                            .frame(width: max(4, g.size.width * fraction))
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

// Color(hex:) è definita in CalendarView.swift — non duplicare qui.
