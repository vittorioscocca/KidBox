//
//  KBHandoff.swift
//  KidBox
//
//  Handoff fra iPhone, iPad e Mac: il dispositivo pubblica dove si trova
//  (sezione e, se c'è, lista to-do o album) e l'altro lo riapre dal Dock o
//  dal selettore app. iOS e Mac sono lo stesso target (Catalyst), quindi la
//  stessa attività va nei due sensi.
//
//  Viaggiano solo identificativi: nessun titolo, nessun contenuto.
//  Il tipo di attività è dichiarato in Info.plist (NSUserActivityTypes).
//

import SwiftUI
import SwiftData

struct KBHandoffTarget: Hashable {
    var section: SidebarSection
    var familyId: String
    var childId: String? = nil
    var listId: String? = nil
    var albumId: String? = nil
    var albumTitle: String? = nil

    private enum Key {
        static let section = "section", familyId = "familyId", childId = "childId"
        static let listId = "listId", albumId = "albumId", albumTitle = "albumTitle"
    }

    var userInfo: [String: String] {
        var info = [Key.section: section.rawValue, Key.familyId: familyId]
        if let childId { info[Key.childId] = childId }
        if let listId { info[Key.listId] = listId }
        if let albumId { info[Key.albumId] = albumId }
        if let albumTitle { info[Key.albumTitle] = albumTitle }
        return info
    }

    init(section: SidebarSection, familyId: String) {
        self.section = section
        self.familyId = familyId
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard let raw = userInfo?[Key.section] as? String,
              let section = SidebarSection(rawValue: raw) else { return nil }
        self.section = section
        familyId = userInfo?[Key.familyId] as? String ?? ""
        childId = userInfo?[Key.childId] as? String
        listId = userInfo?[Key.listId] as? String
        albumId = userInfo?[Key.albumId] as? String
        albumTitle = userInfo?[Key.albumTitle] as? String
    }
}

enum KBHandoff {

    static let activityType = "it.vittorioscocca.kidbox.browse"

    /// Arrivata prima che la radice fosse pronta (app chiusa, login in corso).
    static var pending: KBHandoffTarget?

    /// Dove si trova adesso l'utente. `nil` fuori dalla famiglia.
    @MainActor
    static func current(_ coordinator: AppCoordinator, usesSidebar: Bool) -> KBHandoffTarget? {
        guard coordinator.isAuthenticated, let fid = coordinator.activeFamilyId, !fid.isEmpty else { return nil }
        let path = coordinator.path

        let section: SidebarSection
        if usesSidebar {
            section = coordinator.sidebarSection ?? .dashboard
        } else if let first = path.first,
                  let match = SidebarSection.main.first(where: { $0 != .dashboard && $0.route(familyId: fid) == first }) {
            section = match
        } else if path.isEmpty, coordinator.rootTab == .news {
            section = .news
        } else if path.isEmpty {
            section = .dashboard
        } else {
            // Una pagina che non è la radice di una sezione (impostazioni,
            // profilo…): niente da passare.
            return nil
        }

        var target = KBHandoffTarget(section: section, familyId: fid)
        for route in path {
            switch route {
            case .todoList(familyId: _, childId: let childId, listId: let listId):
                target.section = .todo
                target.childId = childId
                target.listId = listId
            case .photoAlbumDetail(familyId: _, albumId: let albumId, albumTitle: let title, isTripAlbum: _):
                target.section = .photos
                target.albumId = albumId
                target.albumTitle = title
            default:
                break
            }
        }
        return target
    }

    /// Riapre il posto ricevuto. Lista e album solo se la famiglia è la stessa:
    /// in un'altra famiglia non esistono, si apre la sola sezione.
    @MainActor
    static func open(_ target: KBHandoffTarget, coordinator: AppCoordinator,
                     modelContext: ModelContext, usesSidebar: Bool) {
        guard coordinator.isAuthenticated else { pending = target; return }
        pending = nil
        let sameFamily = target.familyId == coordinator.activeFamilyId
        KBLog.navigation.kbInfo("Handoff: apro \(target.section.rawValue) sameFamily=\(sameFamily)")

        if sameFamily, let albumId = target.albumId {
            let route = Route.photoAlbumDetail(familyId: target.familyId, albumId: albumId,
                                               albumTitle: target.albumTitle ?? "")
            if usesSidebar {
                coordinator.path.removeAll()
                coordinator.sidebarSection = .photos
                coordinator.path = [route]
            } else {
                coordinator.openPhotoAlbum(familyId: target.familyId, albumId: albumId, modelContext: modelContext)
            }
            return
        }

        if sameFamily, let listId = target.listId {
            let route = Route.todoList(familyId: target.familyId, childId: target.childId ?? "", listId: listId)
            if usesSidebar {
                coordinator.path.removeAll()
                coordinator.sidebarSection = .todo
                coordinator.path = [route]
            } else {
                coordinator.rootTab = .home
                coordinator.path = [.todo, route]
            }
            return
        }

        KBQuickActions.pending = target.section
        coordinator.consumePendingQuickActionIfNeeded(modelContext: modelContext, usesSidebar: usesSidebar)
    }
}

extension Notification.Name {
    static let kbHandoffReceived = Notification.Name("kbHandoffReceived")
}

/// Pubblica il posto corrente e riapre quello ricevuto. Sta su `RootHostView`,
/// che sa se la shell è a barra laterale; l'attività in arrivo la riceve
/// `KidBoxApp` (sempre montata) e la passa qui.
struct KBHandoffModifier: ViewModifier {
    let usesSidebar: Bool
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .userActivity(KBHandoff.activityType,
                          element: KBHandoff.current(coordinator, usesSidebar: usesSidebar)) { target, activity in
                activity.title = String(localized: target.section.title)
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = false
                activity.isEligibleForPrediction = false
                activity.addUserInfoEntries(from: target.userInfo)
                activity.requiredUserInfoKeys = ["section", "familyId"]
            }
            .onAppear(perform: consumePending)
            .onReceive(NotificationCenter.default.publisher(for: .kbHandoffReceived)) { _ in consumePending() }
    }

    private func consumePending() {
        guard let target = KBHandoff.pending else { return }
        KBHandoff.open(target, coordinator: coordinator, modelContext: modelContext, usesSidebar: usesSidebar)
    }
}
