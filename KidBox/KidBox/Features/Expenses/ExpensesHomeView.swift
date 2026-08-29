//
//  ExpensesHomeView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import Charts
import Combine

private func expensesAppLocale() -> Locale {
    if let lang = Locale.preferredLanguages.first, !lang.isEmpty {
        return Locale(identifier: lang)
    }
    return kbDeviceLocale()
}

// MARK: - Root entry point

struct ExpensesHomeView: View {
    let familyId: String
    /// Se valorizzato, filtra subito per questa categoria (es. Viaggi dal dettaglio viaggio).
    let initialCategoryId: String?
    /// Spesa arrivata da notifica. La si apre appena la sincronizzazione la
    /// porta in locale; fino ad allora si aspetta qui, con lo spinner.
    let highlightExpenseId: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // Il VM viene creato nell'onAppear usando il modelContext dall'environment,
    // lo stesso approccio usato da DocumentFolderView con bind(modelContext:).
    @StateObject private var vm: ExpensesViewModel
    @State private var syncCancellable: AnyCancellable? = nil
    /// Spesa da notifica già aperta: evita di riaprirne il dettaglio a ogni
    /// reload della lista. Gemello di `consumedHighlightExpenseId` su Android.
    @State private var openedPushExpenseId: String? = nil
    /// Si sta aspettando che la sincronizzazione porti la spesa della notifica.
    @State private var isWaitingForPushExpense = false
    
    init(familyId: String, initialCategoryId: String? = nil, highlightExpenseId: String? = nil) {
        self.familyId = familyId
        self.initialCategoryId = initialCategoryId
        self.highlightExpenseId = highlightExpenseId
        // Inizializzazione con un context temporaneo in-memory: viene subito
        // sostituito dal bind(modelContext:) nell'onAppear con il context reale.
        _vm = StateObject(wrappedValue: ExpensesViewModel(
            familyId: familyId,
            modelContext: ModelContext.expensesPreview
        ))
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Nessuna spesa in assoluto: restano solo il messaggio e il
                    // pulsante, senza periodo, totale, grafici e barra selezione.
                    if vm.hasAnyExpense {
                        // Period picker
                        PeriodPickerView(vm: vm)

                        // Summary card
                        TotalSummaryCard(vm: vm)

                        // Due grafici, non due card: sono la stessa domanda
                        // ("quanto spendiamo") vista in due modi, e affiancarle
                        // in verticale avrebbe allungato la pagina per niente.
                        if !vm.monthlyBars.isEmpty {
                            ExpenseChartsCarousel(vm: vm)
                        }

                        // Category breakdown
                        if !vm.categorySlices.isEmpty {
                            CategoryBreakdownView(vm: vm)
                        }
                    }

                    // Expense list
                    ExpenseListSection(vm: vm)
                }
                .padding()
            }
        }
        .trackSectionPresence(.expenses, familyId: familyId)
        .navigationTitle("Spese di famiglia")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Nasconde il "+" durante la selezione multipla
                if !vm.isSelecting {
                    Button {
                        vm.showAddExpense = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $vm.showAddExpense, onDismiss: { vm.reload() }) {
            AddEditExpenseView(vm: vm, expense: nil)
        }
        .sheet(item: $vm.expenseToEdit, onDismiss: { vm.reload() }) { expense in
            AddEditExpenseView(vm: vm, expense: expense)
        }
        .onAppear {
            SyncCenter.shared.startExpensesRealtime(familyId: familyId, modelContext: modelContext)
            syncCancellable = SyncCenter.shared.expensesChanged
                .filter { fid in fid == familyId }
                .receive(on: DispatchQueue.main)
                .sink { fid in vm.reload() }
            vm.bind(modelContext: modelContext)
            if let catId = initialCategoryId {
                vm.selectedCategoryFilter = catId
            }
            vm.reload()
            startPushExpenseWait()
        }
        // Attesa della spesa arrivata da notifica. Vive QUI e non nel dettaglio
        // perché è questa schermata a tenere acceso `startExpensesRealtime`:
        // andando dritti al dettaglio la sync delle spese non partiva nemmeno,
        // quindi da background o ad app chiusa la spesa non poteva arrivare e
        // restava "Spesa non trovata". Come `ExpensesHomeScreen` su Android.
        .overlay {
            if isWaitingForPushExpense {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    HStack(spacing: 14) {
                        ProgressView()
                        Text("Apro la spesa…").font(.subheadline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 12, y: 4)
                }
                .transition(.opacity)
                // Toccando fuori si rinuncia ad aspettare.
                .onTapGesture { isWaitingForPushExpense = false }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isWaitingForPushExpense)
        .onChange(of: vm.expenses.count) { _, _ in openPushExpenseIfNeeded() }
        .onChange(of: highlightExpenseId) { _, _ in startPushExpenseWait() }
        // Scaduta l'attesa si smette di bloccare l'utente: resta la lista spese.
        .task(id: highlightExpenseId) {
            guard highlightExpenseId?.isEmpty == false else { return }
            try? await Task.sleep(nanoseconds: Self.pushExpenseWaitTimeout)
            guard !Task.isCancelled, isWaitingForPushExpense else { return }
            isWaitingForPushExpense = false
            coordinator.globalBannerMessage = "Questo contenuto non è più disponibile."
            KBLog.navigation.kbError("ExpensesHomeView: spesa da push mai arrivata expenseId=\(highlightExpenseId ?? "nil")")
        }
        .onChange(of: vm.period)       { vm.reload() }
        .onChange(of: vm.customStart)  { vm.reload() }
        .onChange(of: vm.customEnd)    { vm.reload() }
        .onChange(of: vm.selectedCategoryFilter) { vm.reload() }
        .onDisappear() {
            SyncCenter.shared.stopExpensesRealtime()
            syncCancellable = nil
        }
        .environment(\.locale, expensesAppLocale())
    }

    // MARK: - Spesa da notifica

    /// Apre il dettaglio della spesa della notifica, una volta sola.
    private func openPushExpenseIfNeeded() {
        guard let eid = highlightExpenseId, openedPushExpenseId != eid else { return }
        guard vm.expenses.contains(where: { $0.id == eid }) else { return }
        openedPushExpenseId = eid
        isWaitingForPushExpense = false
        // La push non parte durante la transizione di ingresso della schermata:
        // si aspetta che sia finita.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            coordinator.navigate(to: .expenseDetail(familyId: familyId, expenseId: eid))
        }
        KBLog.navigation.kbInfo("ExpensesHomeView: apertura dettaglio spesa da push expenseId=\(eid)")
    }

    /// Accende l'attesa se la notifica punta a una spesa non ancora in locale.
    private func startPushExpenseWait() {
        guard let eid = highlightExpenseId, !eid.isEmpty, openedPushExpenseId != eid else { return }
        if vm.expenses.contains(where: { $0.id == eid }) {
            openPushExpenseIfNeeded()
        } else {
            isWaitingForPushExpense = true
        }
    }

    /// Oltre questo limite è più probabile che la spesa non arrivi mai
    /// (cancellata, non visibile) che non un ritardo della sincronizzazione.
    private static let pushExpenseWaitTimeout: UInt64 = 25_000_000_000
}

// MARK: - Period Picker

/// Non più `private`: la usa anche `AllExpensesView`, che è la stessa lista
/// senza il tetto delle quattro righe.
struct PeriodPickerView: View {
    @ObservedObject var vm: ExpensesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExpensePeriod.allCases) { p in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                vm.period = p
                            }
                        } label: {
                            Text(p.displayName)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    vm.period == p
                                    ? Color.accentColor
                                    : Color(.secondarySystemBackground)
                                )
                                .foregroundStyle(vm.period == p ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            
            if vm.period == .custom {
                HStack(spacing: 12) {
                    DatePicker("Da", selection: $vm.customStart, displayedComponents: .date)
                        .labelsHidden()
                    Text("→")
                        .foregroundStyle(.secondary)
                    DatePicker("A", selection: $vm.customEnd, displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Total Summary Card

/// Non più `private`: la usa anche `AllExpensesView`, che deve mostrare lo
/// stesso totale della home — è lo stesso periodo.
struct TotalSummaryCard: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Totale speso")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(vm.totalAmount.formatted(.currency(code: "EUR")))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(vm.expenses.count) spese")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private extension ExpensesViewModel {
    func vm_icon(for slice: CategorySlice) -> String {
        categoryForId(slice.id)?.icon ?? "ellipsis.circle.fill"
    }
}

// MARK: - Monthly Bar Chart

private struct MonthlyBarChartView: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Andamento mensile", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Chart(vm.monthlyBars) { bar in
                BarMark(
                    x: .value("Mese", bar.label),
                    y: .value("Importo", bar.total)
                )
                .foregroundStyle(
                    bar.total == (vm.monthlyBars.max(by: { $0.total < $1.total })?.total ?? 0)
                    ? Color.accentColor
                    : Color.accentColor.opacity(0.55)
                )
                .cornerRadius(6)
                .annotation(position: .top, alignment: .center) {
                    if bar.total > 0 {
                        Text(bar.total.kbCompact)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text(v.kbCompact)
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Carosello grafici

/// Due pagine: l'andamento mese per mese e la media mensile del periodo scelto.
private struct ExpenseChartsCarousel: View {
    @ObservedObject var vm: ExpensesViewModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                MonthlyBarChartView(vm: vm).tag(0)
                MonthlyAverageChartView(vm: vm).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Altezza fissa: dentro uno `ScrollView` un `TabView` senza misura
            // collassa a zero.
            .frame(height: 300)

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }
}

// MARK: - Media mensile

private struct MonthlyAverageChartView: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }

    /// La media si calcola sui mesi del periodo scelto, compresi quelli a zero:
    /// un mese senza spese è un mese in cui non si è speso, non un mese che non
    /// esiste, e ignorarlo gonfierebbe la media.
    private var average: Double {
        guard !vm.monthlyBars.isEmpty else { return 0 }
        return vm.monthlyBars.reduce(0) { $0 + $1.total } / Double(vm.monthlyBars.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Media mensile", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text(average.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }

            Chart {
                ForEach(vm.monthlyBars) { bar in
                    LineMark(
                        x: .value("Mese", bar.label),
                        y: .value("Importo", bar.total)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                    PointMark(
                        x: .value("Mese", bar.label),
                        y: .value("Importo", bar.total)
                    )
                    .foregroundStyle(Color.accentColor)
                }

                // La linea della media: serve a vedere quali mesi stanno sopra.
                RuleMark(y: .value("Media", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text(v.kbCompact).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s).font(.caption2).lineLimit(1)
                        }
                    }
                }
            }
            .frame(height: 200)

            Text("Media dei mesi nel periodo scelto.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Category Breakdown

private struct CategoryBreakdownView: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Per categoria", systemImage: "chart.pie.fill")
                .font(.headline)
            
            // Pie chart (Swift Charts)
            Chart(vm.categorySlices) { slice in
                SectorMark(
                    angle: .value("Totale", slice.total),
                    innerRadius: .ratio(0.58),
                    angularInset: 2
                )
                .foregroundStyle(Color(hex: slice.colorHex) ?? .accentColor)
                .cornerRadius(4)
            }
            .frame(height: 180)
            
            // Legend
            VStack(spacing: 8) {
                ForEach(vm.categorySlices) { slice in
                    Button {
                        withAnimation {
                            vm.selectedCategoryFilter = vm.selectedCategoryFilter == slice.id ? nil : slice.id
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: slice.colorHex)?.opacity(0.15) ?? Color.gray.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: slice.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(hex: slice.colorHex) ?? .accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slice.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                // progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color(.tertiarySystemFill))
                                            .frame(height: 4)
                                        Capsule()
                                            .fill(Color(hex: slice.colorHex) ?? .accentColor)
                                            .frame(width: geo.size.width * CGFloat(slice.percentage / 100), height: 4)
                                    }
                                }
                                .frame(height: 4)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(slice.total.formatted(.currency(code: "EUR")))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(String(format: "%.0f%%", slice.percentage))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(
                        vm.selectedCategoryFilter == slice.id
                        ? (Color(hex: slice.colorHex) ?? .accentColor).opacity(0.1)
                        : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if slice.id != vm.categorySlices.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Expense List Section

struct ExpenseListSection: View {
    /// Quante spese stanno in home prima di "Vedi tutte".
    static let previewCount = 4

    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false
    
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }
    
    private var filteredLabel: String {
        if let catId = vm.selectedCategoryFilter,
           let cat = vm.categories.first(where: { $0.id == catId }) {
            return String(localized: "Spese · \(cat.displayName)")
        }
        return String(localized: "Tutte le spese")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Header ────────────────────────────────────────────────────────
            if vm.hasAnyExpense {
            HStack {
                Label(filteredLabel, systemImage: "list.bullet")
                    .font(.headline)
                Spacer()
                // "Mostra tutto" visibile solo se non siamo in selezione
                if vm.selectedCategoryFilter != nil && !vm.isSelecting {
                    Button("Mostra tutto") {
                        vm.selectedCategoryFilter = nil
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
                // Pulsante Seleziona / Annulla
                if !vm.expenses.isEmpty {
                    Button(vm.isSelecting ? "Annulla" : "Seleziona") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.isSelecting.toggle()
                            vm.selectedExpenseIds.removeAll()
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
            }

            // ── Lista ─────────────────────────────────────────────────────────
            if vm.expenses.isEmpty {
                KBEmptyStateView(
                    systemImage: "receipt",
                    title: "Nessuna spesa",
                    message: "Tieni traccia di quanto esce e per cosa, diviso per categoria. Vedi subito l'andamento del mese e chi ha pagato che cosa.",
                    actionTitle: "Nuova spesa",
                    actionSystemImage: "plus.circle.fill",
                    action: { vm.showAddExpense = true }
                )
            } else {
                // In home solo le ultime quattro: l'elenco completo di un anno
                // di spese farebbe scorrere questa pagina per minuti, e sopra
                // ci sono i totali che si vengono a vedere.
                let preview = Array(vm.expenses.prefix(Self.previewCount))
                VStack(spacing: 0) {
                    ForEach(preview) { expense in
                        ExpenseRowView(expense: expense, vm: vm)
                        if expense.id != preview.last?.id {
                            Divider().padding(.leading, vm.isSelecting ? 68 : 56)
                        }
                    }
                }

                if vm.expenses.count > Self.previewCount, !vm.isSelecting {
                    Divider().padding(.leading, 56)
                    NavigationLink {
                        AllExpensesView(vm: vm)
                    } label: {
                        HStack {
                            Text("Vedi tutte (\(vm.expenses.count))")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // ── Barra azioni selezione ────────────────────────────────────────
            if vm.isSelecting && !vm.expenses.isEmpty {
                Divider()
                HStack {
                    // Seleziona / deseleziona tutto
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if vm.selectedExpenseIds.count == vm.expenses.count {
                                vm.selectedExpenseIds.removeAll()
                            } else {
                                vm.selectedExpenseIds = Set(vm.expenses.map(\.id))
                            }
                        }
                    } label: {
                        let allSelected = vm.selectedExpenseIds.count == vm.expenses.count
                        Label(
                            allSelected ? "Deseleziona tutte" : "Seleziona tutte",
                            systemImage: allSelected ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Elimina selezionate
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Label(
                            "Elimina (\(vm.selectedExpenseIds.count))",
                            systemImage: "trash"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(vm.selectedExpenseIds.isEmpty ? Color.secondary : Color.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.selectedExpenseIds.isEmpty)
                }
                .padding(.top, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Senza spese la sezione non è una card: messaggio e pulsante stanno sullo
        // stesso sfondo della pagina, come nell'empty state di Documenti.
        .padding(vm.hasAnyExpense ? 20 : 0)
        .background(vm.hasAnyExpense ? AnyShapeStyle(cardBg) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: vm.hasAnyExpense ? 16 : 0, style: .continuous))
        .shadow(color: .black.opacity(vm.hasAnyExpense ? 0.06 : 0), radius: 8, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: vm.isSelecting)
        // ── Confirmation dialog eliminazione multipla ─────────────────────────
        .confirmationDialog(
            "Elimina \(vm.selectedExpenseIds.count) \(vm.selectedExpenseIds.count == 1 ? "spesa" : "spese")",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                withAnimation { vm.deleteSelectedExpenses() }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questa azione non può essere annullata.")
        }
    }
}

// MARK: - Expense Row

struct ExpenseRowView: View {
    let expense: KBExpense
    @ObservedObject var vm: ExpensesViewModel
    @EnvironmentObject private var coordinator: AppCoordinator
    
    private var category: KBExpenseCategory? { vm.categoryForId(expense.categoryId) }
    private var isSelected: Bool { vm.selectedExpenseIds.contains(expense.id) }
    
    var body: some View {
        HStack(spacing: 12) {
            
            // ── Cerchio di selezione ──────────────────────────────────────────
            if vm.isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            
            // ── Icona categoria ───────────────────────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: category?.colorHex ?? "#9E9E9E")?.opacity(0.15) ?? Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: category?.icon ?? "ellipsis.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: category?.colorHex ?? "#9E9E9E") ?? .gray)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(expense.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if expense.attachedDocumentId != nil {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(expense.amount.formatted(.currency(code: "EUR")))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if vm.isSelecting {
                // Modalità selezione: toggle check
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                        vm.selectedExpenseIds.remove(expense.id)
                    } else {
                        vm.selectedExpenseIds.insert(expense.id)
                    }
                }
            } else {
                // Modalità normale: naviga al dettaglio
                coordinator.navigate(to: .expenseDetail(familyId: vm.familyId, expenseId: expense.id))
            }
        }
        // Le swipe actions sono disabilitate durante la selezione multipla
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !vm.isSelecting {
                Button(role: .destructive) {
                    vm.deleteExpense(expense)
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
                Button {
                    vm.expenseToEdit = expense
                } label: {
                    Label("Modifica", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
    }
}

// MARK: - Helpers

extension Double {
    var kbCompact: String {
        if self >= 1000 {
            return String(format: "%.1fk", self / 1000)
        }
        return String(format: "%.0f€", self)
    }
}

// Context temporaneo in-memory usato solo per l'init di StateObject.
// Viene subito sostituito da bind(modelContext:) nell'onAppear.
extension ModelContext {
    static var expensesPreview: ModelContext {
        let container = try! ModelContainer(
            for: KBExpense.self, KBExpenseCategory.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
