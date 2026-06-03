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
    
    private var accessibilityLabel: String {
        switch scope {
        case .single(let e): return "Chiedi all'AI sull'esame \(e.name)"
        case .all:           return "Chiedi all'AI sugli esami di \(subjectName)"
        }
    }
    
    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: accessibilityLabel
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
            PediatricExamsAIChatView(subjectName: subjectName, scope: scope)
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
