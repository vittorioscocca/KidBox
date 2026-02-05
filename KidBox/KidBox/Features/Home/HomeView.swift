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
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    // TODO(M3):
                    // - Photo picker (PhotosUI)
                    // - Save locally (FileManager / SwiftData reference)
                    // - Upload to Firebase Storage
                    // - Sync across devices
                    HomeCardView(
                        title: "Foto famiglia",
                        subtitle: "Aggiungi o cambia foto",
                        systemImage: "photo.on.rectangle.angled"
                    ) {
                        KBLog.navigation.debug("Tap Foto famiglia")
                        if !hasFamily { coordinator.navigate(to: .familySettings) }
                    }
                    
                    HomeCardView(
                        title: "Oggi",
                        subtitle: "Routine e cose da fare",
                        systemImage: "sun.max"
                    ) {
                        KBLog.navigation.debug("Tap Oggi")
                        go(.today)
                    }
                    
                    HomeCardView(
                        title: "Calendario",
                        subtitle: "Eventi e impegni",
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
                        KBLog.navigation.debug("Tap Lista condivisa")
                        go(.todo)
                    }
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
