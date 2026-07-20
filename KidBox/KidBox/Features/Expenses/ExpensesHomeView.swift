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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // Il VM viene creato nell'onAppear usando il modelContext dall'environment,
    // lo stesso approccio usato da DocumentFolderView con bind(modelContext:).
    @StateObject private var vm: ExpensesViewModel
    @State private var syncCancellable: AnyCancellable? = nil
    
    init(familyId: String, initialCategoryId: String? = nil) {
        self.familyId = familyId
        self.initialCategoryId = initialCategoryId
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
                    // Period picker
                    PeriodPickerView(vm: vm)
                    
                    // Summary card
                    TotalSummaryCard(vm: vm)
                    
                    // Bar chart
                    if !vm.monthlyBars.isEmpty {
                        MonthlyBarChartView(vm: vm)
                    }
                    
                    // Category breakdown
                    if !vm.categorySlices.isEmpty {
                        CategoryBreakdownView(vm: vm)
                    }
                    
                    // Expense list
                    ExpenseListSection(vm: vm)
                }
                .padding()
            }
        }
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
}

// MARK: - Period Picker

private struct PeriodPickerView: View {
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

private struct TotalSummaryCard: View {
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

private struct ExpenseListSection: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false
    
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }
    
    private var filteredLabel: String {
        if let catId = vm.selectedCategoryFilter,
           let cat = vm.categories.first(where: { $0.id == catId }) {
            return "Spese · \(cat.name)"
        }
        return "Tutte le spese"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // ── Header ────────────────────────────────────────────────────────
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
            
            // ── Lista ─────────────────────────────────────────────────────────
            if vm.expenses.isEmpty {
                ContentUnavailableView(
                    "Nessuna spesa",
                    systemImage: "receipt",
                    description: Text("Aggiungi la prima spesa con il tasto +")
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.expenses) { expense in
                        ExpenseRowView(expense: expense, vm: vm)
                        if expense.id != vm.expenses.last?.id {
                            Divider().padding(.leading, vm.isSelecting ? 68 : 56)
                        }
                    }
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
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
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

private struct ExpenseRowView: View {
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
