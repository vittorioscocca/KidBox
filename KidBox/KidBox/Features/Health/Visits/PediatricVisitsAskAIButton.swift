//
//  PediatricVisitsAskAIButton.swift
//  KidBox
//

import SwiftUI

enum PeriodFilter: String, CaseIterable, Identifiable {
    case sevenDays   = "7 gg"
    case thirtyDays  = "30 gg"
    case threeMonths = "3 mesi"
    case sixMonths   = "6 mesi"
    case oneYear     = "1 anno"
    case all         = "Tutto"
    case custom      = "Personalizzato"
    
    var id: String    { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .sevenDays:    return "7 gg"
        case .thirtyDays:   return "30 gg"
        case .threeMonths:  return "3 mesi"
        case .sixMonths:    return "6 mesi"
        case .oneYear:      return "1 anno"
        case .all:          return "Tutto"
        case .custom:       return "Personalizzato"
        }
    }
    
    var cutoffDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .sevenDays:    return cal.date(byAdding: .day,   value: -7,  to: now)
        case .thirtyDays:   return cal.date(byAdding: .day,   value: -30, to: now)
        case .threeMonths:  return cal.date(byAdding: .month, value: -3,  to: now)
        case .sixMonths:    return cal.date(byAdding: .month, value: -6,  to: now)
        case .oneYear:      return cal.date(byAdding: .year,  value: -1,  to: now)
        case .all, .custom: return nil
        }
    }
}

struct PediatricVisitsAskAIButton: View {
    
    let person:         PediatricPerson
    let visits:         [KBMedicalVisit]
    let selectedPeriod: PeriodFilter
    let action:         ((PediatricPerson, [KBMedicalVisit], PeriodFilter) -> Void)?
    
    @State private var showUpgrade = false
    
    init(
        person:         PediatricPerson,
        visits:         [KBMedicalVisit],
        selectedPeriod: PeriodFilter,
        action:         ((PediatricPerson, [KBMedicalVisit], PeriodFilter) -> Void)? = nil
    ) {
        self.person         = person
        self.visits         = visits
        self.selectedPeriod = selectedPeriod
        self.action         = action
    }
    
    private var personName: String {
        switch person {
        case .child(let child):   return child.name
        case .member(let member): return member.displayName ?? "questo membro"
        }
    }
    
    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: "Chiedi all'AI delle visite di \(personName)"
        ) {
            handleTap()
        }
        .disabled(visits.isEmpty)
        .opacity(visits.isEmpty ? 0.5 : 1)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
                .environmentObject(KBSubscriptionManager.shared)
        }
    }
    
    private func handleTap() {
        guard !visits.isEmpty else { return }
        guard KBSubscriptionManager.shared.currentPlan.includesAI else {
            showUpgrade = true
            return
        }
        action?(person, visits, selectedPeriod)
    }
}
