//
//  ExpensesViewModel.swift
//  KidBox
//


import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Period

enum ExpensePeriod: String, CaseIterable, Identifiable {
    case oneMonth    = "1 mese"
    case threeMonths = "3 mesi"
    case sixMonths   = "6 mesi"
    case oneYear     = "1 anno"
    case custom      = "Personalizzato"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .oneMonth:    return "1 mese"
        case .threeMonths: return "3 mesi"
        case .sixMonths:   return "6 mesi"
        case .oneYear:     return "1 anno"
        case .custom:      return "Personalizzato"
        }
    }
    
    func dateRange(relativeTo today: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let end = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: today)!)
        switch self {
        case .oneMonth:
            return (cal.date(byAdding: .month, value: -1, to: cal.startOfDay(for: today))!, end)
        case .threeMonths:
            return (cal.date(byAdding: .month, value: -3, to: cal.startOfDay(for: today))!, end)
        case .sixMonths:
            return (cal.date(byAdding: .month, value: -6, to: cal.startOfDay(for: today))!, end)
        case .oneYear:
            return (cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: today))!, end)
        case .custom:
            return (cal.startOfDay(for: today), end)
        }
    }
}

// MARK: - Chart data

struct MonthlyExpenseBar: Identifiable {
    let id: String
    let label: String
    let total: Double
    var categoryBreakdown: [String: Double]
}

struct CategorySlice: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let icon: String
    let total: Double
    let percentage: Double
}

// MARK: - ViewModel

@MainActor
final class ExpensesViewModel: ObservableObject {
    
    // MARK: Published state
    
    @Published var period: ExpensePeriod = .sixMonths
    @Published var customStart: Date = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @Published var customEnd: Date = Date()
    
    @Published var expenses:       [KBExpense]         = []
    @Published var categories:     [KBExpenseCategory] = []
    @Published var monthlyBars:    [MonthlyExpenseBar] = []
    @Published var categorySlices: [CategorySlice]     = []
    @Published var totalAmount:    Double               = 0
    
    @Published var isLoading:               Bool    = false
    @Published var errorMessage:            String? = nil
    @Published var showAddExpense:          Bool    = false
    @Published var expenseToEdit:           KBExpense? = nil
    @Published var showFilters:             Bool    = false
    @Published var selectedCategoryFilter:  String? = nil
    
    // MARK: Multi-selezione
    @Published var isSelecting:         Bool        = false
    @Published var selectedExpenseIds:  Set<String> = []
    
    let familyId: String
    private var modelContext: ModelContext
    
    // MARK: Init
    
    init(familyId: String, modelContext: ModelContext) {
        self.familyId     = familyId
        self.modelContext = modelContext
        KBExpenseCategory.seedDefaults(familyId: familyId, context: modelContext)
        try? modelContext.save()
        reload()
    }
    
    // MARK: bind
    
    func bind(modelContext: ModelContext) {
        self.modelContext = modelContext
        KBExpenseCategory.seedDefaults(familyId: familyId, context: modelContext)
        try? modelContext.save()
    }
    
    // MARK: Date range
    
    var effectiveDateRange: (start: Date, end: Date) {
        if period == .custom {
            let cal = Calendar.current
            return (
                cal.startOfDay(for: customStart),
                cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: customEnd)!)
            )
        }
        return period.dateRange()
    }
    
    // MARK: Reload
    
    func reload() {
        isLoading = true
        defer { isLoading = false }
        
        let fid        = familyId
        let range      = effectiveDateRange
        let rangeStart = range.start
        let rangeEnd   = range.end
        
        let expDescriptor = FetchDescriptor<KBExpense>(
            predicate: #Predicate {
                $0.familyId == fid &&
                $0.isDeleted == false &&
                $0.date >= rangeStart &&
                $0.date < rangeEnd
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(expDescriptor)) ?? []
        
        if let catFilter = selectedCategoryFilter {
            expenses = fetched.filter { $0.categoryId == catFilter }
        } else {
            expenses = fetched
        }
        
        let catDescriptor = FetchDescriptor<KBExpenseCategory>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        categories = (try? modelContext.fetch(catDescriptor)) ?? []
        
        computeCharts(from: expenses, in: range)
    }
    
    // MARK: Chart computation
    
    private func computeCharts(from list: [KBExpense], in range: (start: Date, end: Date)) {
        totalAmount = list.reduce(0) { $0 + $1.amount }
        
        let cal = Calendar.current
        var monthDict: [String: Double] = [:]
        for exp in list {
            let comps = cal.dateComponents([.year, .month], from: exp.date)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            monthDict[key, default: 0] += exp.amount
        }
        
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: range.start))!
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: range.end))!
        var bars: [MonthlyExpenseBar] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM ''yy"
        if let lang = Locale.preferredLanguages.first, !lang.isEmpty {
            fmt.locale = Locale(identifier: lang)
        } else {
            fmt.locale = kbDeviceLocale()
        }
        
        while cursor <= endMonth {
            let comps = cal.dateComponents([.year, .month], from: cursor)
            let key   = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            bars.append(MonthlyExpenseBar(id: key, label: fmt.string(from: cursor),
                                          total: monthDict[key] ?? 0, categoryBreakdown: [:]))
            cursor = cal.date(byAdding: .month, value: 1, to: cursor)!
        }
        monthlyBars = bars
        
        var catDict: [String: Double] = [:]
        for exp in list { catDict[exp.categoryId ?? "_none", default: 0] += exp.amount }
        let total = list.reduce(0) { $0 + $1.amount }
        
        categorySlices = catDict.compactMap { (catId, amount) -> CategorySlice? in
            if catId == "_none" {
                return CategorySlice(id: "_none", name: "Altro", colorHex: "#9E9E9E",
                                     icon: "ellipsis.circle.fill", total: amount,
                                     percentage: total > 0 ? amount / total * 100 : 0)
            }
            guard let cat = categories.first(where: { $0.id == catId }) else { return nil }
            return CategorySlice(id: catId, name: cat.name, colorHex: cat.colorHex, icon: cat.icon,
                                 total: amount, percentage: total > 0 ? amount / total * 100 : 0)
        }.sorted { $0.total > $1.total }
    }
    
    // MARK: CRUD
    
    func addExpense(title: String, amount: Double, date: Date, categoryId: String?,
                    notes: String?, attachedDocumentId: String?, createdByUid: String?) {
        _ = addExpenseReturning(title: title, amount: amount, date: date,
                                categoryId: categoryId, notes: notes, createdByUid: createdByUid)
    }
    
    @discardableResult
    func addExpenseReturning(title: String, amount: Double, date: Date, categoryId: String?,
                             notes: String?, createdByUid: String?) -> KBExpense {
        let exp = KBExpense(
            familyId:           familyId,
            title:              title,
            amount:             amount,
            date:               date,
            categoryId:         categoryId,
            notes:              notes,
            attachedDocumentId: nil,
            createdByUid:       createdByUid
        )
        modelContext.insert(exp)
        try? modelContext.save()
        
        // ── SYNC ──────────────────────────────────────────────────────────────
        SyncCenter.shared.enqueueExpenseUpsert(
            expenseId: exp.id,
            familyId:  familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        // ─────────────────────────────────────────────────────────────────────
        
        reload()
        return exp
    }
    
    func updateExpense(_ expense: KBExpense, title: String, amount: Double,
                       date: Date, categoryId: String?, notes: String?) {
        expense.title      = title
        expense.amount     = amount
        expense.date       = date
        expense.categoryId = categoryId
        expense.notes      = notes
        expense.updatedAt  = Date()
        try? modelContext.save()
        
        // ── SYNC ──────────────────────────────────────────────────────────────
        SyncCenter.shared.enqueueExpenseUpsert(
            expenseId: expense.id,
            familyId:  familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        // ─────────────────────────────────────────────────────────────────────
        
        reload()
    }
    
    func deleteExpense(_ expense: KBExpense) {
        expense.isDeleted = true
        expense.updatedAt = Date()
        try? modelContext.save()
        
        // ── SYNC ──────────────────────────────────────────────────────────────
        SyncCenter.shared.enqueueExpenseDelete(
            expenseId: expense.id,
            familyId:  familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        // ─────────────────────────────────────────────────────────────────────
        
        reload()
    }
    
    // MARK: Bulk delete (multi-selezione)
    
    func deleteSelectedExpenses() {
        let toDelete = expenses.filter { selectedExpenseIds.contains($0.id) }
        toDelete.forEach { expense in
            expense.isDeleted = true
            expense.updatedAt = Date()
            SyncCenter.shared.enqueueExpenseDelete(
                expenseId: expense.id,
                familyId:  familyId,
                modelContext: modelContext
            )
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        selectedExpenseIds.removeAll()
        isSelecting = false
        reload()
    }
    
    func categoryForId(_ id: String?) -> KBExpenseCategory? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }
}
