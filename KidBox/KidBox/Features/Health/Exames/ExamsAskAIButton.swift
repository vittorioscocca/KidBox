//
//  ExamsAskAIButton.swift
//  KidBox
//

import SwiftUI

struct ExamsAskAIButton: View {
    
    let subjectName: String
    let scope: ExamAIChatScope
    
    @State private var showConsent = false
    @State private var showChat    = false
    @State private var showUpgrade = false
    
    private var isEmpty: Bool { scope.exams.isEmpty }

    /// L'assistente unico, centrato sull'esame o sugli esami della persona.
    private var focus: AgentFocus {
        let personId = scope.exams.first?.childId ?? ""
        switch scope {
        case .single(let e):
            return AgentFocus(personId: personId, personName: subjectName, scope: .exam(id: e.id), detail: e.name.trimmingCharacters(in: .whitespacesAndNewlines))
        case .all:
            return AgentFocus(personId: personId, personName: subjectName, scope: .exams)
        }
    }

    private var accessibilityLabel: String {
        switch scope {
        case .single(let e): return "Chiedi all'AI sull'esame \(e.name)"
        case .all:           return "Chiedi all'AI sugli esami di \(subjectName)"
        }
    }

    private var upgradeMessage: LocalizedStringKey {
        switch scope {
        case .single: return "ai_upgrade_exam_detail"
        case .all:    return "ai_upgrade_exams_home"
        }
    }

    private var upgradeTriggerFeature: String {
        switch scope {
        case .single: return "ai_upgrade_exam_detail"
        case .all:    return "ai_upgrade_exams_home"
        }
    }

    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: accessibilityLabel
        ) {
            handleTap()
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(contextualMessage: upgradeMessage, triggerFeature: upgradeTriggerFeature)
                .environmentObject(KBSubscriptionManager.shared)
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheetOrMacPush(isPresented: $showChat) {
            AgentChatSheet(focus: focus)
        }
    }
    
    private func handleTap() {
        guard !isEmpty else { return }
        guard KBSubscriptionManager.shared.isAIAccessible else {
            showUpgrade = true
            switch scope {
            case .single: AppAnalytics.aiPaywallShown(context: "ai_upgrade_exam_detail")
            case .all:    AppAnalytics.aiPaywallShown(context: "ai_upgrade_exams_home")
            }
            return
        }
        if !AISettings.shared.consentGiven {
            showConsent = true
            return
        }
        showChat = true
    }
}
