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
            UpgradeSheetView()
                .environmentObject(KBSubscriptionManager.shared)
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheet(isPresented: $showChat) {
            MedicalAIChatView(visit: visit, child: child)
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
