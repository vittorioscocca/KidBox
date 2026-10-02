//
//  AskAIButton.swift
//  KidBox
//

import SwiftUI

struct AskAIButton: View {
    
    let visit: KBMedicalVisit
    let child: KBChild
    
    @State private var showConsent  = false
    @State private var showChat     = false
    @State private var showUpgrade  = false
    
    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: "Chiedi all'AI"
        ) {
            handleTap()
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(contextualMessage: "ai_upgrade_visit_detail", triggerFeature: "ai_upgrade_visit_detail")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheetOrMacPush(isPresented: $showChat) {
            AgentChatSheet(focus: AgentFocus(
                personId: child.id,
                personName: child.name,
                scope: .visit(id: visit.id),
                detail: String(
                    format: NSLocalizedString("Visita del %@", comment: "Assistant focus label: visit date"),
                    visit.date.formatted(.dateTime.day().month(.abbreviated).year().locale(kbDeviceLocale()))
                )
            ))
        }
    }
    
    private func handleTap() {
        guard KBSubscriptionManager.shared.isAIAccessible else {
            showUpgrade = true
            AppAnalytics.aiPaywallShown(context: "ai_upgrade_visit_detail")
            return
        }
        if !AISettings.shared.consentGiven {
            showConsent = true
            return
        }
        showChat = true
    }
}
