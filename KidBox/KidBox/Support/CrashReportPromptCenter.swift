//
//  CrashReportPromptCenter.swift
//  KidBox
//

import Foundation
import Combine

/// Stato UI per il consenso al report anonimo (presentato da RootHostView).
@MainActor
final class CrashReportPromptCenter: ObservableObject {

    static let shared = CrashReportPromptCenter()

    struct Prompt: Identifiable {
        let id = UUID()
        let issueCount: Int
        let onSend: () -> Void
        let onDecline: () -> Void
    }

    @Published var activePrompt: Prompt?

    private init() {}

    func present(issueCount: Int, onSend: @escaping () -> Void, onDecline: @escaping () -> Void) {
        activePrompt = Prompt(issueCount: issueCount, onSend: onSend, onDecline: onDecline)
    }

    func dismiss() {
        activePrompt = nil
    }
}
