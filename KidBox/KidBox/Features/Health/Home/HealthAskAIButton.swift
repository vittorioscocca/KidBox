//
//  HealthAskAIButton.swift
//  KidBox
//

import SwiftUI

struct HealthAskAIButton: View {

    let subjectName: String
    let subjectId:   String

    @State private var showConsent = false
    @State private var showChat    = false
    @State private var showUpgrade = false

    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: "Chiedi all'AI sulla salute di \(subjectName)"
        ) {
            handleTap()
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(contextualMessage: "ai_upgrade_health_home", triggerFeature: "ai_upgrade_health_home")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheetOrMacPush(isPresented: $showChat) {
            // L'assistente unico, centrato su questa persona: i dati li legge da sé.
            AgentChatSheet(focus: AgentFocus(personId: subjectId, personName: subjectName, scope: .person))
        }
    }

    private func handleTap() {
        guard KBSubscriptionManager.shared.isAIAccessible else {
            showUpgrade = true
            AppAnalytics.aiPaywallShown(context: "ai_upgrade_health_home")
            return
        }
        if !AISettings.shared.consentGiven {
            showConsent = true
            return
        }
        showChat = true
    }
}
