//
//  ExamsAskAIButton.swift
//  KidBox
//
//  Created by vscocca on 09/03/26.
//

import SwiftUI

/// Bottone AI per gli esami medici.
/// Usabile sia in PediatricExamDetailView (scope .single)
/// che in PediatricExamsView (scope .all).
struct ExamsAskAIButton: View {
    
    let subjectName: String
    let scope: ExamAIChatScope
    
    @ObservedObject private var settings = AISettings.shared
    
    @State private var showConsent = false
    @State private var showChat    = false
    
    private var isEmpty: Bool { scope.exams.isEmpty }
    
    var body: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: accessibilityLabel
        ) {
            handleTap()
        }
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.5 : 1)
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheet(isPresented: $showChat) {
            PediatricExamsAIChatView(subjectName: subjectName, scope: scope)
        }
    }
    
    private var accessibilityLabel: String {
        switch scope {
        case .single(let e): return "Chiedi all'AI sull'esame \(e.name)"
        case .all:           return "Chiedi all'AI sugli esami di \(subjectName)"
        }
    }
    
    private func handleTap() {
        guard !isEmpty else { return }
        if !settings.consentGiven { showConsent = true; return }
        showChat = true
    }
}
