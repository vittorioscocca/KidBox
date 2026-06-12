//
//  AISettingsView.swift
//  KidBox
//

import SwiftUI
import StoreKit

struct AISettingsView: View {
    
    @StateObject private var viewModel = AISettingsViewModel()
    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager
    @State private var showConsent             = false
    @State private var showUpgrade             = false
    @State private var showManageSubscriptions = false
    @State private var showOfferCodeRedemption = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
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
    
    private var plan: KBPlan { subscriptionManager.currentPlan }
    
    // MARK: - Body
    
    var body: some View {
        List {
            
            // MARK: - Piano corrente
            Section {
                currentPlanCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .id(subscriptionManager.currentPlan)
            }
            
            // MARK: - Banner abbonamento in scadenza
            if subscriptionManager.isCancelledButActive,
               let expiry = subscriptionManager.subscriptionExpirationDate {
                Section {
                    aiExpiringBanner(expirationDate: expiry)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            
            // MARK: - Intro
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .padding(10)
                            .background(.blue.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Assistente AI")
                                .font(.headline)
                            Text(plan.includesAI ? "Incluso nel tuo piano \(plan.displayName)" : "Disponibile con Pro o Max")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Collega il tuo assistente AI e trasforma KidBox nel punto di riferimento intelligente della tua famiglia. Salute, routine, documenti, agenda: tutto il contesto che già tieni in app, a disposizione di un assistente che conosce davvero i tuoi figli.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(cardBackground)
            }
            
            // MARK: - Toggle (solo se piano include AI)
            if plan.includesAI {
                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.aiEnabled },
                        set: { newValue in
                            if newValue && !viewModel.consentGiven {
                                showConsent = true
                            } else {
                                viewModel.toggleAIEnabled(newValue)
                            }
                        }
                    )) {
                        Label("Attiva assistente AI", systemImage: "brain.head.profile")
                    }
                    .listRowBackground(cardBackground)
                    
                    if let info = viewModel.infoText {
                        Text(info)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(cardBackground)
                    }
                    
                } footer: {
                    Text("Puoi disattivarlo in qualsiasi momento. I dati inviati all'AI sono quelli che scegli di condividere, visita per visita.")
                        .font(.caption)
                }
            } else {
                Section {
                    aiLockedBanner
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            
            // MARK: - Utilizzo oggi
            if plan.includesAI && viewModel.aiEnabled {
                Section("Utilizzo oggi") {
                    if viewModel.loadingUsage {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Caricamento…").foregroundStyle(.secondary)
                        }
                        .listRowBackground(cardBackground)
                    } else if let usage = viewModel.usage {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(usage.usageToday) di \(plan.aiDailyLimit) messaggi usati oggi")
                                    .font(.subheadline)
                                Spacer()
                                if usage.isNearLimit {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                            ProgressView(
                                value: Double(usage.usageToday),
                                total: Double(plan.aiDailyLimit)
                            )
                            .tint(usage.isNearLimit ? .orange : .blue)
                            
                            if usage.isNearLimit && plan != .max {
                                if subscriptionManager.isFamilyOwner {
                                    Button {
                                        showUpgrade = true
                                    } label: {
                                        Label("Passa a \(plan == .free ? "Pro" : "Max") per più messaggi",
                                              systemImage: "arrow.up.circle")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NonOwnerUpgradeNotice()
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(cardBackground)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                            .listRowBackground(cardBackground)
                    }
                }
                .task { await viewModel.loadUsage() }
            }

            // MARK: - Chat salute (contesto AI)
            if plan.includesAI && viewModel.aiEnabled {
                Section {
                    Picker(selection: Binding(
                        get: { viewModel.healthContextSendPreference },
                        set: { viewModel.setHealthContextSendPreference($0) }
                    )) {
                        ForEach(HealthContextSendPreference.allCases) { pref in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pref.displayName)
                                Text(pref.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(pref)
                        }
                    } label: {
                        Label("Contesto chat Salute", systemImage: "heart.text.clipboard")
                    }
                    .pickerStyle(.inline)
                    .listRowBackground(cardBackground)
                } header: {
                    Text("Chat Salute AI")
                } footer: {
                    Text("Con profili sanitari molto ampi, KidBox può inviare tutti i referti o un riassunto. Puoi cambiare questa scelta in qualsiasi momento; se scegli «Chiedi ogni volta», vedrai il dialogo prima di ogni invio.")
                        .font(.caption)
                }
            }
            
            // MARK: - Privacy / Consenso
            if plan.includesAI && viewModel.consentGiven, let date = viewModel.consentDate {
                Section("Privacy") {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Consenso fornito").font(.subheadline)
                            Text(date.formatted(date: .long, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(cardBackground)
                    
                    Button(role: .destructive) {
                        viewModel.revokeConsent()
                    } label: {
                        Label("Revoca consenso e disattiva", systemImage: "hand.raised")
                    }
                    .listRowBackground(cardBackground)
                }
            }
            
            // MARK: - Sintesi settimanale
            if plan.includesAI {
                Section("Sintesi settimanale") {
                    Toggle(isOn: Binding(
                        get: { WeeklySummaryService.shared.isEnabled },
                        set: { WeeklySummaryService.shared.isEnabled = $0 }
                    )) {
                        Label("Recap ogni lunedì mattina", systemImage: "calendar.badge.clock")
                    }
                    .listRowBackground(cardBackground)

                    Toggle(isOn: Binding(
                        get: { DailyBriefingService.shared.isEnabled },
                        set: { DailyBriefingService.shared.isEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Briefing quotidiano AI", systemImage: "sun.max.fill")
                            Text("Notifica ogni mattina alle 8:00 con gli impegni del giorno")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(cardBackground)

                    Toggle(isOn: Binding(
                        get: { HealthPatternAnalyzerService.shared.isEnabled },
                        set: { HealthPatternAnalyzerService.shared.isEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pattern salute AI")
                            Text("Analisi mensile della storia sanitaria dei figli")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(cardBackground)

                    infoRow(
                        icon: "sparkles",
                        color: KBTheme.tint,
                        title: "Come funziona",
                        body: "Ogni lunedì alle 08:00 ricevi una notifica con un breve recap generato dall'AI: scadenze, cure, eventi chiave e un suggerimento pratico per la settimana."
                    )
                    .listRowBackground(cardBackground)
                }
            }
            
            // MARK: - Document Intelligence
            if plan.includesAI && viewModel.consentGiven {
                Section("Analisi documenti") {
                    Toggle(isOn: Binding(
                        get: { AISettings.shared.documentIntelligenceEnabled },
                        set: { AISettings.shared.documentIntelligenceEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Smista automaticamente i documenti", systemImage: "doc.text.magnifyingglass")
                            Text("Quando importi un documento, l'AI lo legge e propone azioni (spese, eventi, scadenze, salute). Consuma messaggi AI: 1 per pagina analizzata.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(cardBackground)
                }
            }

            // MARK: - Come funziona
            Section("Come funziona") {
                infoRow(icon: "lock.shield.fill", color: .green,
                        title: "Dati al sicuro",
                        body: "Nessuna API key sul tuo dispositivo. Tutto passa per i server KidBox.")
                .listRowBackground(cardBackground)
                
                infoRow(icon: "gauge.with.dots.needle.bottom.50percent", color: .blue,
                        title: "Limite giornaliero",
                        body: "Ogni piano include un numero di messaggi AI al giorno per membro. Il contatore si azzera a mezzanotte.")
                .listRowBackground(cardBackground)
                
                infoRow(icon: "exclamationmark.triangle", color: .orange,
                        title: "Non è un parere medico",
                        body: "L'AI spiega e informa. Per decisioni cliniche consulta sempre il tuo medico.")
                .listRowBackground(cardBackground)
            }
            
            // MARK: - Gestione abbonamento
            if subscriptionManager.currentPlan != .free {
                Section("Abbonamento") {
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
            
            if subscriptionManager.isFamilyOwner {
                Section {
                    Button {
                        showOfferCodeRedemption = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Riscatta codice offerta")
                                Text("Codice promozionale App Store")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "giftcard.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .listRowBackground(cardBackground)
                } footer: {
                    Text("Si apre il foglio di sistema Apple per inserire il codice. Il piano famiglia si aggiorna dopo il riscatto.")
                        .font(.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Assistente AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load()
            viewModel.healthContextSendPreference = AISettings.shared.healthContextSendPreference
            Task { await subscriptionManager.loadPlan() }
        }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await subscriptionManager.refreshCurrentEntitlement() }
            }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet {
                viewModel.recordConsent()
            }
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
                .environmentObject(subscriptionManager)
        }
    }
    
    // MARK: - Piano corrente card
    
    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(planColor(plan).opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: planIcon(plan))
                        .font(.title3)
                        .foregroundStyle(planColor(plan))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Piano \(plan.displayName)")
                        .font(.headline)
                    HStack(spacing: 8) {
                        if plan.includesAI {
                            Label("\(plan.aiDailyLimit) msg AI/giorno", systemImage: "sparkles")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label("AI non inclusa", systemImage: "sparkles.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if subscriptionManager.isCancelledButActive {
                    Button("Gestisci") {
                        showManageSubscriptions = true
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
                } else if plan != .max, subscriptionManager.isFamilyOwner {
                    Button("Upgrade") { showUpgrade = true }
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(planColor(.pro)))
                }
            }
            
            if !subscriptionManager.isCancelledButActive, plan != .max, !subscriptionManager.isFamilyOwner {
                NonOwnerUpgradeNotice()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(planColor(plan).opacity(0.07))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - AI expiring banner
    
    private func aiExpiringBanner(expirationDate: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale    = kbDeviceLocale()
        let dateStr = formatter.string(from: expirationDate)
        
        return HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Abbonamento in scadenza")
                    .font(.subheadline.bold())
                Text("L'AI sarà disponibile fino al \(dateStr), poi passerai al piano Free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Rinnova") {
                showManageSubscriptions = true
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.orange))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.08))
        )
        .padding(.horizontal)
    }
    
    // MARK: - AI locked banner (piano Free)
    
    private var aiLockedBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("L'assistente AI è disponibile con Pro o Max")
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
            Text("Passa a Pro per 20 messaggi AI al giorno per membro, o a Max per 100.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if subscriptionManager.isFamilyOwner {
                Button {
                    showUpgrade = true
                } label: {
                    Text("Scopri i piani")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Capsule().fill(Color(red: 0.35, green: 0.6, blue: 0.85)))
                }
                .buttonStyle(.plain)
            } else {
                NonOwnerUpgradeNotice()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.06))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func infoRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func planColor(_ p: KBPlan) -> Color {
        switch p {
        case .free: return .gray
        case .pro:  return Color(red: 0.35, green: 0.6, blue: 0.85)
        case .max:  return Color(red: 0.55, green: 0.35, blue: 0.9)
        }
    }
    
    private func planIcon(_ p: KBPlan) -> String {
        switch p {
        case .free: return "person.circle"
        case .pro:  return "star.circle.fill"
        case .max:  return "crown.fill"
        }
    }
}

// MARK: - Upgrade Sheet (riutilizzabile da più punti)

struct UpgradeSheetView: View {
    
    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showOfferCodeRedemption = false
    
    private let tint     = Color(red: 0.35, green: 0.6, blue: 0.85)
    private let maxColor = Color(red: 0.55, green: 0.35, blue: 0.9)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Hero
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(tint)
                        Text("Sblocca il meglio di KidBox")
                            .font(.title2.bold())
                        Text("Un piano per tutta la famiglia. Un solo abbonamento copre tutti i membri.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 8)
                    
                    // Piano Pro
                    planCard(
                        plan:     .pro,
                        color:    tint,
                        icon:     "star.circle.fill",
                        features: ["5 GB storage famiglia", "20 msg AI/giorno per membro", "Sintesi settimanale AI"]
                    )
                    
                    // Piano Max
                    planCard(
                        plan:     .max,
                        color:    maxColor,
                        icon:     "crown.fill",
                        features: ["20 GB storage famiglia", "100 msg AI/giorno per membro", "Sintesi settimanale AI", "Supporto prioritario"]
                    )
                    
                    // Ripristina
                    Button("Ripristina acquisti precedenti") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    
                    if subscriptionManager.isFamilyOwner {
                        Button {
                            showOfferCodeRedemption = true
                        } label: {
                            Label("Riscatta codice offerta o promozionale", systemImage: "giftcard.fill")
                                .font(.footnote)
                        }
                        .foregroundStyle(tint)
                    }
                    
                    // ✅ Legal footer — FUORI dalla planCard, visibile a tutti
                    legalFooter
                }
                .padding()
            }
            .navigationTitle("Piani KidBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .task {
            await subscriptionManager.loadProducts()
        }
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
        .alert("Errore acquisto", isPresented: .init(
            get: { subscriptionManager.purchaseError != nil },
            set: { if !$0 { } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(subscriptionManager.purchaseError ?? "")
        }
    }
    
    // MARK: - Plan card
    
    @ViewBuilder
    private func planCard(plan: KBPlan, color: Color, icon: String, features: [String]) -> some View {
        let isCurrent   = subscriptionManager.currentPlan == plan
        let isCancelled = isCurrent && subscriptionManager.isCancelledButActive
        let expiryDate  = subscriptionManager.subscriptionExpirationDate
        let product     = subscriptionManager.storeProduct(for: plan)
        
        VStack(alignment: .leading, spacing: 14) {
            
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(plan.displayName)
                    .font(.headline)
                if !plan.badge.isEmpty {
                    Text(plan.badge)
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
                Spacer()
                if isCurrent {
                    Text(isCancelled ? "In scadenza" : "Piano attuale")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(isCancelled ? Color.orange : color))
                }
            }
            
            // Data scadenza se cancellato
            if isCancelled, let expiry = expiryDate {
                Label {
                    Text("Attivo fino al \(expiry.formatted(date: .long, time: .omitted))")
                        .font(.caption)
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                .foregroundStyle(.orange)
            }
            
            // Feature list
            ForEach(features, id: \.self) { f in
                Label(f, systemImage: "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            
            // Bottone acquisto — solo testo, niente legalFooter dentro
            if !isCurrent || isCancelled {
                if subscriptionManager.isFamilyOwner {
                    Button {
                        Task { await subscriptionManager.purchase(plan) }
                    } label: {
                        HStack {
                            if subscriptionManager.isPurchasing {
                                ProgressView().controlSize(.small).tint(.white)
                                Text("Acquisto in corso…")
                            } else {
                                let priceStr = product?.displayPrice ?? plan.monthlyPrice
                                Text(isCancelled
                                     ? "Riattiva · \(priceStr)/mese"
                                     : "Abbonati · \(priceStr)/mese")
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isCancelled ? Color.orange : color)
                        )
                    }
                    .disabled(subscriptionManager.isPurchasing)
                    .buttonStyle(.plain)
                } else {
                    NonOwnerUpgradeNotice()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.07)
                      : color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isCurrent ? color : Color.clear, lineWidth: 2)
                )
        )
    }
    
    // MARK: - Legal footer
    private var legalFooter: some View {
        let privacyURL = URL(string: "https://vittorioscocca.github.io/KidBox/privacy/")!
        let termsURL   = URL(string: "https://vittorioscocca.github.io/KidBox/terms/")!
        
        return VStack(spacing: 6) {
            Text("L'abbonamento si rinnova automaticamente ogni mese. Puoi annullare in qualsiasi momento dalle impostazioni del tuo account Apple.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: privacyURL)
                Text("·").foregroundStyle(.secondary)
                Link("Termini di utilizzo", destination: termsURL)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

#Preview {
    NavigationStack { AISettingsView() }
        .environmentObject(KBSubscriptionManager.shared)
}
