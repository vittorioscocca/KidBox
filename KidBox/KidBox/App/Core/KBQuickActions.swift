//
//  KBQuickActions.swift
//  KidBox
//
//  Scorciatoie del tocco lungo sull'icona dell'app (Home Screen Quick Actions).
//
//  Le quattro voci sono le sezioni che il dispositivo apre di più: ogni volta
//  che dalla Home si entra in una sezione se ne incrementa il contatore (locale,
//  non va sul server), e le scorciatoie si riscrivono da lì. Finché i dati sono
//  pochi, a parità di conteggio vincono le sezioni di default.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

extension Notification.Name {
    /// Una scorciatoia è stata toccata: l'app la apre appena è pronta.
    static let kbQuickActionPending = Notification.Name("kidbox.quickAction.pending")
}

enum KBQuickActions {

    private static let usageKey = "KidBox.sectionUsage"
    private static let typePrefix = "it.vittorioscocca.kidbox.open."
    private static let maxItems = 4

    /// Sezioni mostrate quando non c'è ancora uno storico d'uso, in ordine.
    private static let defaultOrder: [SidebarSection] = [.calendar, .todo, .shopping, .chat]

    /// Sezione chiesta da una scorciatoia e non ancora aperta.
    static var pending: SidebarSection?

    // MARK: - Uso

    private static var usage: [String: Int] {
        UserDefaults.standard.dictionary(forKey: usageKey) as? [String: Int] ?? [:]
    }

    /// Sezioni che ha senso proporre: niente Home, Famiglia, Profilo, Impostazioni.
    private static func isEligible(_ section: SidebarSection) -> Bool {
        switch section {
        case .dashboard, .family, .profile, .settings: return false
        case .chat: return KBChatAvailability.isEnabled
        default: return true
        }
    }

    /// Da chiamare quando l'utente entra nella radice di una sezione.
    static func record(_ section: SidebarSection) {
        guard isEligible(section) else { return }
        var counts = usage
        counts[section.rawValue, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: usageKey)
        refresh()
    }

    /// Le sezioni da proporre, dalla più usata.
    static func topSections() -> [SidebarSection] {
        let counts = usage
        func rank(_ s: SidebarSection) -> Int { defaultOrder.firstIndex(of: s) ?? Int.max }
        return SidebarSection.main
            .filter(isEligible)
            .sorted {
                let a = counts[$0.rawValue] ?? 0, b = counts[$1.rawValue] ?? 0
                return a != b ? a > b : rank($0) < rank($1)
            }
            .prefix(maxItems)
            .map { $0 }
    }

    // MARK: - Scorciatoie

    /// Riscrive le voci del tocco lungo. Anche a ogni ritorno in primo piano,
    /// così i titoli seguono la lingua scelta nell'app.
    static func refresh() {
        #if !targetEnvironment(macCatalyst)
        let items = topSections().map { section in
            UIApplicationShortcutItem(
                type: typePrefix + section.rawValue,
                localizedTitle: String(localized: section.title),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: section.systemImage),
                userInfo: nil
            )
        }
        DispatchQueue.main.async { UIApplication.shared.shortcutItems = items }
        #endif
    }

    /// Mette da parte la sezione chiesta. Restituisce `false` se non è nostra.
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type.hasPrefix(typePrefix),
              let section = SidebarSection(rawValue: String(item.type.dropFirst(typePrefix.count)))
        else { return false }
        pending = section
        NotificationCenter.default.post(name: .kbQuickActionPending, object: nil)
        return true
    }
}

/// Serve solo a ricevere la scorciatoia quando l'app è già in memoria
/// (a freddo la legge `AppDelegate` dalle opzioni di connessione).
final class KBSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(KBQuickActions.handle(shortcutItem))
    }
}

/// Ascolta la scorciatoia arrivata ad app già aperta. Sta in un modificatore a
/// parte perché il `body` di `RootHostView` è già al limite del type-checker.
struct KBQuickActionListener: ViewModifier {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    let usesSidebar: Bool

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .kbQuickActionPending)) { _ in
            coordinator.consumePendingQuickActionIfNeeded(modelContext: modelContext, usesSidebar: usesSidebar)
        }
    }
}
