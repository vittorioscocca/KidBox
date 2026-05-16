//
//  KidBoxAIActionPipeline.swift
//  KidBox
//
//  Shared processing + execution of KIDBOX_ACTIONS for every AI chat.
//

import Foundation
import SwiftUI
import SwiftData
import FirebaseAuth

@MainActor
enum KidBoxAIActionPipeline {

    struct Outcome {
        let displayText: String
        let executionSummary: String?
        let didAutoExecute: Bool
    }

    static func processReply(
        _ reply: String,
        modelContext: ModelContext,
        familyId: String,
        defaultChildId: String? = nil,
        pendingGroceryNames: [String] = []
    ) async -> Outcome {
        let processed = PlanningAIActionBlock.process(reply)
        guard !processed.actions.isEmpty, !familyId.isEmpty else {
            return Outcome(
                displayText: processed.displayText,
                executionSummary: nil,
                didAutoExecute: false
            )
        }

        let uid = Auth.auth().currentUser?.uid ?? "ai-agent"
        let children = fetchChildren(familyId: familyId, modelContext: modelContext)
        let actions = processed.actions.map { action in
            injectDefaultChild(action, defaultChildId: defaultChildId)
        }

        let executor = PlanningActionExecutor(
            modelContext: modelContext,
            familyId: familyId,
            uid: uid,
            children: children,
            pendingGroceryNames: pendingGroceryNames
        )
        let summary = await executor.execute(actions)
        return Outcome(
            displayText: processed.displayText,
            executionSummary: summary,
            didAutoExecute: true
        )
    }

    static func fetchPendingGroceryNames(
        familyId: String,
        modelContext: ModelContext
    ) -> [String] {
        let fid = familyId
        let descriptor = FetchDescriptor<KBGroceryItem>(
            predicate: #Predicate { $0.familyId == fid && !$0.isPurchased && !$0.isDeleted }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.map(\.name)
    }

    private static func fetchChildren(familyId: String, modelContext: ModelContext) -> [KBChild] {
        let fid = familyId
        let descriptor = FetchDescriptor<KBChild>(
            predicate: #Predicate { $0.familyId == fid }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

}

// MARK: - Toast feedback

private struct AIActionExecutionToastModifier: ViewModifier {
    @Binding var summary: String?
    var tint: Color = KBTheme.tint

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(tint.opacity(0.9)))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self.summary = nil
                        }
                    }
            }
        }
    }
}

extension View {
    func aiActionExecutionToast(summary: Binding<String?>, tint: Color = KBTheme.tint) -> some View {
        modifier(AIActionExecutionToastModifier(summary: summary, tint: tint))
    }
}

extension KidBoxAIActionPipeline {
    private static func injectDefaultChild(
        _ action: PlanningExecutableAction,
        defaultChildId: String?
    ) -> PlanningExecutableAction {
        guard let defaultChildId, action.childId == nil else { return action }
        return PlanningExecutableAction(
            type: action.type,
            items: action.items,
            title: action.title,
            body: action.body,
            notes: action.notes,
            category: action.category,
            dueAt: action.dueAt,
            startAt: action.startAt,
            endAt: action.endAt,
            isAllDay: action.isAllDay,
            childId: defaultChildId,
            listId: action.listId
        )
    }
}
