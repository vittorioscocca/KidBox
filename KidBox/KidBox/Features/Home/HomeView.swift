//
//  HomeView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import FirebaseAuth
import OSLog
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    private var activeFamily: KBFamily? { families.first }
    private var hasFamily: Bool { activeFamily != nil }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                
                header
                
                // Quick actions grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    
                    HomeCardView(
                        title: "Oggi",
                        subtitle: "Routine, cure e cose da fare",
                        systemImage: "sun.max"
                    ) {
                        KBLog.navigation.debug("Tap Oggi")
                        go(.today)
                    }
                    
                    HomeCardView(
                        title: "Calendario",
                        subtitle: "Eventi e affidamenti",
                        systemImage: "calendar"
                    ) {
                        KBLog.navigation.debug("Tap Calendario")
                        go(.calendar)
                    }
                    
                    HomeCardView(
                        title: "Todo",
                        subtitle: "Lista condivisa",
                        systemImage: "checklist"
                    ) {
                        KBLog.navigation.debug("Tap Todo")
                        go(.todo)
                    }
                    
                    HomeCardView(
                        title: "Cure",
                        subtitle: "Promemoria e “fatto / non fatto”",
                        systemImage: "cross.case"
                    ) {
                        KBLog.navigation.debug("Tap Cure")
                        //go(.care)
                    }
                    
                    HomeCardView(
                        title: "Documenti",
                        subtitle: "Carte importanti del bimbo",
                        systemImage: "doc.text"
                    ) {
                        KBLog.navigation.debug("Tap Documenti")
                        //go(.documents)
                    }
                    
                    HomeCardView(
                        title: "Spese",
                        subtitle: "Rette, visite, extra",
                        systemImage: "eurosign.circle"
                    ) {
                        KBLog.navigation.debug("Tap Spese")
                        //go(.expenses)
                    }
                    
                    HomeCardView(
                        title: "Chat",
                        subtitle: "Coordinamento famiglia",
                        systemImage: "message"
                    ) {
                        KBLog.navigation.debug("Tap Chat")
                        //go(.chat)
                    }
                    
                    HomeCardView(
                        title: "Timeline",
                        subtitle: "Storia e tappe del bimbo",
                        systemImage: "clock.arrow.circlepath"
                    ) {
                        KBLog.navigation.debug("Tap Timeline")
                        //go(.timeline)
                    }
                }
                
                // Optional: “Foto famiglia” la sposterei in Profile o nelle impostazioni,
                // ma se vuoi tenerla qui, mettila come card singola sotto la grid.
                HomeCardView(
                    title: "Foto famiglia",
                    subtitle: "Aggiungi o cambia foto",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    KBLog.navigation.debug("Tap Foto famiglia")
                    if !hasFamily { coordinator.navigate(to: .familySettings) }
                    else {/* coordinator.navigate(to: .familyPhoto) */} // opzionale
                }
                
                InviteCardView {
                    KBLog.navigation.debug("Tap Invita altro genitore")
                    go(.inviteCode, else: .joinFamily)
                }
                
                LogoutCardView {
                    signOut()
                }
            }
            .padding()
        }
        .navigationTitle("KidBox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    KBLog.navigation.debug("Tap Profile")
                    coordinator.navigate(to: .profile)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profilo")
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    KBLog.navigation.debug("Tap settings")
                    coordinator.navigate(to: .settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Impostazioni")
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Benvenuto 👋")
                .font(.title2).bold()
            Text("Organizziamo la giornata senza discutere.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
    
    private func signOut() {
        coordinator.signOut(modelContext: modelContext)
    }
    
    private func go(_ routeIfFamily: Route, else routeIfNoFamily: Route = .familySettings) {
        coordinator.navigate(to: hasFamily ? routeIfFamily : routeIfNoFamily)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppCoordinator())
    }
    .modelContainer(ModelContainerProvider.makeContainer(inMemory: true))
}
