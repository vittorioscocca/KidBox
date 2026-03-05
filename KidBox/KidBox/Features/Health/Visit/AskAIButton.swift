//
//  AskAIButton.swift
//  KidBox
//

import SwiftUI

struct AskAIButton: View {
    
    let visit: KBMedicalVisit
    let child: KBChild
    
    @ObservedObject private var settings = AISettings.shared
    
    @State private var showSettings = false
    @State private var showConsent  = false
    @State private var showChat     = false
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            Label("Chiedi all'AI", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .controlSize(.large)
        .sheet(isPresented: $showSettings) {
            NavigationStack { AISettingsView() }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet {
                showChat = true
            }
        }
        .sheet(isPresented: $showChat) {
            MedicalAIChatView(visit: visit, child: child)
        }
    }
    
    private func handleTap() {
        if !settings.consentGiven {
            showConsent = true
            return
        }
        showChat = true
    }
}
