//
//  MacShellView.swift
//  KidBox
//
//  Desktop-class shell for Mac Catalyst: a NavigationSplitView with a
//  persistent sidebar of the app sections and a detail column that reuses
//  the exact same feature views as iOS/iPad via `AppCoordinator.makeDestination`.
//
//  Design notes:
//  - This file is compiled ONLY on Mac Catalyst (`#if targetEnvironment(macCatalyst)`),
//    so the iPhone/iPad UI is completely untouched.
//  - The sidebar selects a *section*; the detail column hosts its own
//    `NavigationStack` bound to `coordinator.path`, so drill-down inside a
//    section (e.g. opening a note detail) keeps working via `coordinator.navigate(to:)`.
//  - Section → root view mapping mirrors the Home grid cards, so titles,
//    icons and colors stay consistent with the rest of the app.
//  - On Mac the Home grid is redundant (the sidebar replaces it), so the
//    `Home` section shows a lightweight dashboard (`MacDashboardView`) instead.
//

#if targetEnvironment(macCatalyst)

import SwiftUI
import SwiftData

// MARK: - Sections

/// Top-level sections shown in the Mac sidebar.
///
/// Order here = order in the sidebar. Each case maps to a `Route` already
/// handled by `AppCoordinator.makeDestination(for:)` (except `.dashboard`,
/// which is rendered as a dedicated Mac dashboard).
enum MacSection: String, CaseIterable, Identifiable {
    case dashboard
    case calendar
    case todo
    case notes
    case shopping
    case photos
    case health
    case chat
    case documents
    case expenses
    case wallet
    case passwords
    case location
    case pets
    case homeItems
    case vehicles
    case travel
    case assistant
    // Account group
    case family
    case profile
    case settings

    var id: String { rawValue }

    /// Main app sections (top group in the sidebar).
    static let main: [MacSection] = [
        .dashboard, .calendar, .todo, .notes, .shopping, .photos, .health,
        .chat, .documents, .expenses, .wallet, .passwords, .location, .pets,
        .homeItems, .vehicles, .travel, .assistant
    ]

    /// Account / family management sections (bottom group in the sidebar).
    static let account: [MacSection] = [.family, .profile, .settings]

    var title: String {
        switch self {
        case .dashboard: return "Home"
        case .calendar:  return "Calendario"
        case .todo:      return "To-Do"
        case .notes:     return "Note"
        case .shopping:  return "Lista della Spesa"
        case .photos:    return "Foto e video"
        case .health:    return "Salute"
        case .chat:      return "Chat"
        case .documents: return "Documenti"
        case .expenses:  return "Spese"
        case .wallet:    return "Wallet"
        case .passwords: return "Password"
        case .location:  return "Posizione"
        case .pets:      return "Animali domestici"
        case .homeItems: return "Casa"
        case .vehicles:  return "Garage"
        case .travel:    return "Viaggi"
        case .assistant: return "Assistente"
        case .family:    return "Family"
        case .profile:   return "Profilo"
        case .settings:  return "Impostazioni"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .calendar:  return "calendar"
        case .todo:      return "checklist"
        case .notes:     return "note.text"
        case .shopping:  return "cart.fill"
        case .photos:    return "photo.stack.fill"
        case .health:    return "heart.fill"
        case .chat:      return "message.fill"
        case .documents: return "doc.text"
        case .expenses:  return "eurosign.circle"
        case .wallet:    return "ticket.fill"
        case .passwords: return "key.fill"
        case .location:  return "location.fill"
        case .pets:      return "pawprint.fill"
        case .homeItems: return "house.fill"
        case .vehicles:  return "car.fill"
        case .travel:    return "suitcase.fill"
        case .assistant: return "brain.head.profile"
        case .family:    return "person.2.fill"
        case .profile:   return "person.crop.circle"
        case .settings:  return "gearshape.fill"
        }
    }

    /// Accent color for the sidebar icon (mirrors the Home cards).
    var tint: Color {
        switch self {
        case .dashboard: return .orange
        case .calendar:  return .purple
        case .todo:      return .blue
        case .notes:     return .yellow
        case .shopping:  return .green
        case .photos:    return .pink
        case .health:    return .red
        case .chat:      return .green
        case .documents: return .orange
        case .expenses:  return .mint
        case .wallet:    return .indigo
        case .passwords: return .blue
        case .location:  return .cyan
        case .pets:      return .orange
        case .homeItems: return .brown
        case .vehicles:  return .gray
        case .travel:    return .teal
        case .assistant: return .purple
        case .family:    return .teal
        case .profile:   return .blue
        case .settings:  return .gray
        }
    }

    /// Sections whose root view needs a `familyId` to render meaningfully.
    var requiresFamily: Bool {
        switch self {
        case .dashboard, .todo, .chat, .documents, .family, .profile, .assistant, .settings:
            return false
        case .calendar, .notes, .shopping, .photos, .health, .expenses, .wallet,
             .passwords, .location, .pets, .homeItems, .vehicles, .travel:
            return true
        }
    }

    /// The root `Route` for this section. `familyId` is ignored for sections
    /// that don't need it. `.dashboard` has no route (rendered directly).
    func route(familyId: String) -> Route {
        switch self {
        case .dashboard: return .home // unused: dashboard is rendered directly
        case .calendar:  return .calendar(familyId: familyId)
        case .todo:      return .todo
        case .notes:     return .notesHome(familyId: familyId)
        case .shopping:  return .shoppingList(familyId: familyId)
        case .photos:    return .familyPhotos(familyId: familyId)
        case .health:    return .pediatricChildSelector(familyId: familyId)
        case .chat:      return .chat
        case .documents: return .documentsHome
        case .expenses:  return .expensesHome(familyId: familyId)
        case .wallet:    return .walletHome(familyId: familyId)
        case .passwords: return .passwordsHome(familyId: familyId)
        case .location:  return .familyLocation(familyId: familyId)
        case .pets:      return .petsHome(familyId: familyId)
        case .homeItems: return .homeItemsHome(familyId: familyId)
        case .vehicles:  return .vehiclesHome(familyId: familyId)
        case .travel:    return .travelList(familyId: familyId)
        case .assistant: return .askExpert
        case .family:    return .familySettings
        case .profile:   return .profile
        case .settings:  return .settings
        }
    }
}

// MARK: - Shell

struct MacShellView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    /// Fallback resolution of the active family (mirrors RootHostView logic).
    @Query(sort: \KBFamily.updatedAt, order: .reverse)
    private var families: [KBFamily]

    @State private var selection: MacSection? = .dashboard
    @State private var searchText: String = ""

    private var resolvedFamilyId: String? {
        coordinator.activeFamilyId ?? families.first?.id
    }

    /// Sections matching the current search query (case/diacritic-insensitive).
    private func filtered(_ sections: [MacSection]) -> [MacSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }
        return sections.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        NavigationSplitView {
            let mainResults = filtered(MacSection.main)
            let accountResults = filtered(MacSection.account)
            List(selection: $selection) {
                if mainResults.isEmpty && accountResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    if !mainResults.isEmpty {
                        Section {
                            ForEach(mainResults) { sidebarRow($0) }
                        }
                    }
                    if !accountResults.isEmpty {
                        Section("Account") {
                            ForEach(accountResults) { sidebarRow($0) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Cerca sezione")
            .navigationTitle("KidBox")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack(path: $coordinator.path) {
                rootDetail
                    .navigationDestination(for: Route.self) { route in
                        coordinator.makeDestination(for: route)
                    }
            }
            .navigationSplitViewColumnWidth(min: 560, ideal: 820)
        }
        .navigationSplitViewStyle(.balanced)
        // Switching section starts a fresh navigation stack in the detail column.
        .onChange(of: selection) { _, _ in
            coordinator.path.removeAll()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ section: MacSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(section.tint)
        }
        .tag(section)
    }

    @ViewBuilder
    private var rootDetail: some View {
        if let section = selection {
            if section == .dashboard {
                MacDashboardView()
            } else if section.requiresFamily {
                if let fid = resolvedFamilyId, !fid.isEmpty {
                    coordinator.makeDestination(for: section.route(familyId: fid))
                } else {
                    ContentUnavailableView(
                        "Nessuna famiglia attiva",
                        systemImage: "person.2.slash",
                        description: Text("Crea o unisciti a una famiglia per usare questa sezione.")
                    )
                }
            } else {
                coordinator.makeDestination(for: section.route(familyId: resolvedFamilyId ?? ""))
            }
        } else {
            ContentUnavailableView(
                "Seleziona una sezione",
                systemImage: "sidebar.left",
                description: Text("Scegli una voce dalla barra laterale.")
            )
        }
    }
}

// MARK: - Mac Dashboard (no card grid)

/// Landing view for the `Home` section on Mac.
///
/// The card grid used on iPhone/iPad is intentionally omitted here — navigation
/// lives in the sidebar. We keep the family hero as a welcome banner.
private struct MacDashboardView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]

    private var activeFamily: KBFamily? {
        ActiveFamilyResolver.family(from: families, activeFamilyId: coordinator.activeFamilyId)
    }
    private var hasFamily: Bool { activeFamily != nil }

    private var activeMembersCount: Int {
        guard let fid = activeFamily?.id, !fid.isEmpty else { return 0 }
        return members.filter { $0.familyId == fid && !$0.isDeleted }.count
    }

    private var heroPhotoURL: URL? {
        guard let s = activeFamily?.heroPhotoURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeroCard(
                    title: hasFamily ? (activeFamily?.name ?? "La tua famiglia") : "Benvenuto 👋",
                    subtitle: hasFamily ? "" : "Crea o unisciti a una famiglia per iniziare.",
                    dateText: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    rightBadgeText: hasFamily ? "\(activeMembersCount) membri" : "",
                    photoURL: heroPhotoURL,
                    photoUpdatedAt: activeFamily?.heroPhotoUpdatedAt,
                    scale: activeFamily?.heroPhotoScale ?? 1.0,
                    offsetX: activeFamily?.heroPhotoOffsetX ?? 0.0,
                    offsetY: activeFamily?.heroPhotoOffsetY ?? 0.0,
                    isBusy: false
                ) {
                    coordinator.navigate(to: .familySettings)
                }
                .id(activeFamily?.heroPhotoUpdatedAt ?? activeFamily?.updatedAt)

                Text("Scegli una sezione dalla barra laterale per iniziare.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
    }
}

#endif
