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
    
    private var isEmpty: Bool {
        exams.isEmpty && visits.isEmpty && treatments.isEmpty && vaccines.isEmpty
    }
    
    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: "Chiedi all'AI sulla salute di \(subjectName)"
        ) {
            handleTap()
        }
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.5 : 1)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
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
        guard !isEmpty else { return }
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
