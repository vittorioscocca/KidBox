//
//  HomeFAB.swift
//  KidBox
//

import SwiftUI
import SwiftData
import Combine

// MARK: - FABUsageTracker
//
// Tiene traccia di quante volte l'utente ha usato ogni azione del FAB.
// Persistito in UserDefaults — leggero, locale, nessuna dipendenza di rete.

@MainActor
final class FABUsageTracker: ObservableObject {
    
    static let shared = FABUsageTracker()
    private init() {}
    
    private let key = "kb_fab_usage_v1"
    
    private var counts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    
    /// Incrementa il contatore per un'azione
    func record(_ actionId: String) {
        var c = counts
        c[actionId, default: 0] += 1
        counts = c
        objectWillChange.send()
    }
    
    /// Restituisce le top N azioni per utilizzo
    func topActions(from all: [FABAction], count n: Int) -> [FABAction] {
        let c = counts
        return all
            .sorted { (c[$0.id] ?? 0) > (c[$1.id] ?? 0) }
            .prefix(n)
            .map { $0 }
    }
    
    func count(for actionId: String) -> Int {
        counts[actionId] ?? 0
    }
    
    var totalUsage: Int {
        counts.values.reduce(0, +)
    }
}

// MARK: - FABAction

struct FABAction: Identifiable {
    let id:    String
    let icon:  String
    let label: String
    let color: Color
}

extension FABAction {
    /// Catalogo completo — Chat, Salute, Animali, Casa e Garage inclusi
    static let all: [FABAction] = [
        FABAction(id: "expense",  icon: "eurosign.circle.fill",  label: "Spesa",        color: Color(red: 1.00, green: 0.60, blue: 0.20)),
        FABAction(id: "event",    icon: "calendar.badge.plus",   label: "Evento",       color: Color(red: 0.60, green: 0.35, blue: 0.85)),
        FABAction(id: "todo",     icon: "checklist",             label: "To-Do",        color: Color(red: 0.20, green: 0.55, blue: 0.90)),
        FABAction(id: "note",     icon: "note.text.badge.plus",  label: "Nota",         color: Color(red: 1.00, green: 0.75, blue: 0.10)),
        FABAction(id: "grocery",  icon: "cart.badge.plus",       label: "Lista spesa",  color: Color(red: 0.25, green: 0.70, blue: 0.45)),
        FABAction(id: "chat",     icon: "bubble.left.fill",      label: "Messaggio",    color: Color(red: 0.20, green: 0.75, blue: 0.40)),
        FABAction(id: "health",   icon: "cross.case.fill",       label: "Salute",       color: Color(red: 0.90, green: 0.25, blue: 0.25)),
        FABAction(id: "documents", icon: "doc.text.fill", label: "Documenti", color: Color(red: 0.25, green: 0.55, blue: 0.90)),
        FABAction(id: "pets", icon: "pawprint.fill", label: "Animali", color: Color(red: 1.00, green: 0.58, blue: 0.00)),
        FABAction(id: "home_items", icon: "house.fill", label: "Casa", color: Color(red: 0.55, green: 0.41, blue: 0.08)),
        FABAction(id: "vehicles", icon: "car.fill", label: "Garage", color: Color(red: 0.10, green: 0.10, blue: 0.10)),
    ]
}

// MARK: - HomeFAB

struct HomeFAB: View {
    
    let familyId: String
    @Binding var isExpanded: Bool
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var tracker = FABUsageTracker.shared
    @State private var showAddExpense = false
    
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let light  = UIImpactFeedbackGenerator(style: .light)
    
    /// Le 4 azioni più usate — si riordinano automaticamente ad ogni utilizzo
    private var visibleActions: [FABAction] {
        tracker.topActions(from: FABAction.all, count: 4)
    }
    
    // MARK: Body
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            
            if isExpanded {
                // Hint adattivo — visibile solo le prime 5 volte in assoluto
                if tracker.totalUsage < 5 {
                    Text("Si adatta al tuo utilizzo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                }
                
                // Azioni adattive (mostrate dal basso verso l'alto)
                ForEach(visibleActions.reversed()) { action in
                    actionRow(action)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.85)),
                                removal: .opacity.combined(with: .scale(scale: 0.85))
                            )
                        )
                }
            }
            
            mainButton
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.70), value: isExpanded)
        .animation(.spring(response: 0.36, dampingFraction: 0.70), value: visibleActions.map(\.id))
        .sheet(isPresented: $showAddExpense) {
            AddEditExpenseView(
                vm: ExpensesViewModel(familyId: familyId, modelContext: modelContext),
                expense: nil
            )
        }
    }
    
    // MARK: Main button
    
    private var mainButton: some View {
        Button {
            impact.impactOccurred()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.70)) {
                isExpanded.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.75, blue: 0.25),
                                Color(red: 0.95, green: 0.38, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(
                        color: Color(red: 0.95, green: 0.38, blue: 0.10).opacity(0.45),
                        radius: 14, x: 0, y: 6
                    )
                
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isExpanded)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: Action row
    
    private func actionRow(_ action: FABAction) -> some View {
        Button {
            light.impactOccurred()
            tracker.record(action.id)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                handleAction(action.id)
            }
        } label: {
            HStack(spacing: 10) {
                Text(action.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(
                        colorScheme == .dark
                        ? Color(red: 0.18, green: 0.18, blue: 0.18)
                        : Color.white,
                        in: Capsule()
                    )
                    .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
                
                ZStack {
                    Circle()
                        .fill(action.color)
                        .frame(width: 42, height: 42)
                        .shadow(color: action.color.opacity(0.38), radius: 7, x: 0, y: 3)
                    Image(systemName: action.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: Navigation
    
    private func handleAction(_ id: String) {
        switch id {
        case "expense":
            showAddExpense = true
        case "event":
            coordinator.navigate(to: .calendar(familyId: familyId, highlightEventId: nil))
        case "todo":
            coordinator.navigate(to: .todo)
        case "note":
            coordinator.navigate(to: .notesHome(familyId: familyId))
        case "grocery":
            coordinator.navigate(to: .shoppingList(familyId: familyId))
        case "chat":
            coordinator.navigate(to: .chat)
        case "health":
            coordinator.navigate(to: .pediatricChildSelector(familyId: familyId))
        case "documents":
            coordinator.navigate(to: .documentsHome)
        case "pets":
            coordinator.navigate(to: .petsHome(familyId: familyId))
        case "home_items":
            coordinator.navigate(to: .homeItemsHome(familyId: familyId))
        case "vehicles":
            coordinator.navigate(to: .vehiclesHome(familyId: familyId))
        default:
            break
        }
    }
}
