//
//  KBHandoff.swift
//  KidBox
//
//  Handoff fra iPhone, iPad e Mac: il dispositivo pubblica dove si trova
//  (sezione e, se c'è, lista to-do o album) e l'altro lo riapre dal Dock o
//  dal selettore app. iOS e Mac sono lo stesso target (Catalyst), quindi la
//  stessa attività va nei due sensi.
//
//  Oltre al posto viaggia la bozza che si sta scrivendo (`KBHandoffDraft`):
//  un to-do, una voce della spesa, un evento, un messaggio della chat; per
//  una nota o una scheda su qualcosa che esiste già, solo il suo id. La bozza
//  va da dispositivo a dispositivo con Handoff (Apple, stesso account iCloud),
//  non passa dai server di KidBox.
//  Il tipo di attività è dichiarato in Info.plist (NSUserActivityTypes).
//

import SwiftUI
import SwiftData
import Combine

struct KBHandoffTarget: Hashable {
    var section: SidebarSection
    var familyId: String
    var childId: String? = nil
    var listId: String? = nil
    var albumId: String? = nil
    var albumTitle: String? = nil
    var draft: KBHandoffDraft? = nil

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
        if let draft {
            info[KBHandoffDraft.kindKey] = draft.kind.rawValue
            for (k, v) in draft.fields { info[KBHandoffDraft.fieldPrefix + k] = v }
        }
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
        if let raw = userInfo?[KBHandoffDraft.kindKey] as? String, let kind = KBHandoffDraft.Kind(rawValue: raw) {
            var fields: [String: String] = [:]
            for (k, v) in userInfo ?? [:] {
                if let k = k as? String, k.hasPrefix(KBHandoffDraft.fieldPrefix), let v = v as? String {
                    fields[String(k.dropFirst(KBHandoffDraft.fieldPrefix.count))] = v
                }
            }
            draft = KBHandoffDraft(kind: kind, fields: fields)
        }
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
        KBLog.navigation.kbInfo("Handoff: apro \(target.section.rawValue) sameFamily=\(sameFamily) draft=\(target.draft?.kind.rawValue ?? "-")")

        // La bozza la prende la schermata d'arrivo (lista, calendario, chat):
        // solo nella stessa famiglia, altrove non avrebbe dove andare.
        KBHandoffDraftCenter.shared.incoming = sameFamily ? target.draft : nil

        // Una nota si apre direttamente: è già salvata, viaggia solo il suo id.
        if sameFamily, target.draft?.kind == .note, let noteId = target.draft?.fields["noteId"] {
            KBHandoffDraftCenter.shared.incoming = nil
            let route = Route.noteDetail(familyId: target.familyId, noteId: noteId)
            if usesSidebar {
                coordinator.path.removeAll()
                coordinator.sidebarSection = .notes
                coordinator.path = [route]
            } else {
                coordinator.rootTab = .home
                coordinator.path = [.notesHome(familyId: target.familyId), route]
            }
            return
        }

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

// MARK: - Bozze

/// Quello che si sta scrivendo. I campi sono stringhe (le date in secondi dal
/// 1970) e restano corti: Handoff consiglia pochi KB in tutto.
struct KBHandoffDraft: Hashable {
    enum Kind: String { case todo, grocery, event, chat, note }

    var kind: Kind
    var fields: [String: String]

    static let kindKey = "draftKind"
    static let fieldPrefix = "d."

    init(kind: Kind, fields: [String: String?]) {
        self.kind = kind
        var clean: [String: String] = [:]
        for (k, v) in fields {
            guard let v, !v.isEmpty else { continue }
            clean[k] = String(v.prefix(1500))
        }
        self.fields = clean
    }

    init(kind: Kind, fields: [String: String]) {
        self.init(kind: kind, fields: fields.mapValues { Optional($0) })
    }

    func date(_ key: String) -> Date? {
        fields[key].flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    static func dateString(_ date: Date?) -> String? {
        date.map { String(Int($0.timeIntervalSince1970)) }
    }
}

/// Chi scrive pubblica qui la bozza; il modificatore di Handoff la mette
/// nell'attività. All'arrivo, `incoming` aspetta la schermata che la sa usare.
@MainActor
final class KBHandoffDraftCenter: ObservableObject {
    static let shared = KBHandoffDraftCenter()

    @Published private(set) var outgoing: KBHandoffDraft?
    /// Una bozza che nessuna schermata prende entro un minuto (si è finiti
    /// altrove) non deve saltare fuori più tardi.
    @Published var incoming: KBHandoffDraft? {
        didSet { incomingAt = incoming == nil ? nil : Date() }
    }
    private var incomingAt: Date?
    private var owner: UUID?

    func publish(_ draft: KBHandoffDraft?, owner: UUID) {
        self.owner = owner
        if outgoing != draft { outgoing = draft }
    }

    func withdraw(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        outgoing = nil
    }

    /// La bozza in arrivo, se è del tipo giusto; letta una volta sola.
    func take(_ kind: KBHandoffDraft.Kind) -> KBHandoffDraft? {
        guard let draft = incoming, draft.kind == kind else { return nil }
        let at = incomingAt
        incoming = nil
        if let at, Date().timeIntervalSince(at) > 60 { return nil }
        return draft
    }
}

private struct KBHandoffDraftPublisher: ViewModifier {
    let draft: KBHandoffDraft?
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { KBHandoffDraftCenter.shared.publish(draft, owner: owner) }
            .onChange(of: draft) { _, new in KBHandoffDraftCenter.shared.publish(new, owner: owner) }
            .onDisappear { KBHandoffDraftCenter.shared.withdraw(owner: owner) }
    }
}

/// Riceve la bozza del suo tipo quando compare e quando ne arriva una nuova.
private struct KBHandoffDraftReceiver: ViewModifier {
    let kind: KBHandoffDraft.Kind
    let action: (KBHandoffDraft) -> Void
    @ObservedObject private var center = KBHandoffDraftCenter.shared

    func body(content: Content) -> some View {
        content
            .onAppear { if let d = center.take(kind) { action(d) } }
            .onChange(of: center.incoming) { _, _ in if let d = center.take(kind) { action(d) } }
    }
}

extension View {
    /// Pubblica la bozza di questa schermata per Handoff (`nil` = niente da passare).
    func handoffDraft(_ draft: KBHandoffDraft?) -> some View {
        modifier(KBHandoffDraftPublisher(draft: draft))
    }

    /// Prende la bozza arrivata da un altro dispositivo.
    func onHandoffDraft(_ kind: KBHandoffDraft.Kind, perform action: @escaping (KBHandoffDraft) -> Void) -> some View {
        modifier(KBHandoffDraftReceiver(kind: kind, action: action))
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
    @ObservedObject private var drafts = KBHandoffDraftCenter.shared

    private var target: KBHandoffTarget? {
        guard var t = KBHandoff.current(coordinator, usesSidebar: usesSidebar) else { return nil }
        t.draft = drafts.outgoing
        return t
    }

    func body(content: Content) -> some View {
        content
            .userActivity(KBHandoff.activityType, element: target) { target, activity in
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
