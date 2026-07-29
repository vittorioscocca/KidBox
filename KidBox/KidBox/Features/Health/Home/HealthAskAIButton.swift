//
//  HealthAskAIButton.swift
//  KidBox
//

import SwiftUI

struct HealthAskAIButton: View {

    let subjectName: String
    let subjectId:   String
    let exams:       [KBMedicalExam]
    let visits:      [KBMedicalVisit]
    let treatments:  [KBTreatment]
    let vaccines:    [KBVaccine]

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
            UpgradeSheetView(contextualMessage: "ai_upgrade_health_home")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheetOrMacPush(isPresented: $showChat) {
            HealthAIChatView(
                subjectName: subjectName,
                subjectId:   subjectId,
                exams:       exams,
                visits:      visits,
                treatments:  treatments,
                vaccines:    vaccines
            )
        }
    }

    private func handleTap() {
        guard KBSubscriptionManager.shared.currentPlan.includesAI else {
            showUpgrade = true
            return
        }
        if !AISettings.shared.consentGiven {
            showConsent = true
            return
        }
        showChat = true
    }
}
