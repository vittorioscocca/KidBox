//
//  HealthAskAIButton.swift
//  KidBox
//
//  Floating AI button used in PediatricHomeView.
//  Works for both KBChild and KBFamilyMember — callers pass subjectName + subjectId.
//

import SwiftUI

struct HealthAskAIButton: View {
    
    let subjectName: String
    let subjectId: String
    let exams: [KBMedicalExam]
    let visits: [KBMedicalVisit]
    let treatments: [KBTreatment]
    let vaccines: [KBVaccine]
    
    @ObservedObject private var settings = AISettings.shared
    
    @State private var showConsent = false
    @State private var showChat    = false
    
    /// Disable only when there is absolutely nothing to discuss.
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
        .sheet(isPresented: $showConsent) {
            AIConsentSheet { showChat = true }
        }
        .sheet(isPresented: $showChat) {
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
        if !settings.consentGiven { showConsent = true; return }
        showChat = true
    }
}
