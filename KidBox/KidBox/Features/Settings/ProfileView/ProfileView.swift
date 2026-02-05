//
//  ProfileView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import FirebaseAuth
import OSLog

struct ProfileView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        List {
            Section("Account") {
                if let user = Auth.auth().currentUser {
                    Text("UID: \(user.uid)")
                        .font(.caption)
                        .textSelection(.enabled)
                    
                    if let email = user.email {
                        Text("Email: \(email)")
                    }
                } else {
                    Text("Non autenticato")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    signOut()
                } label: {
                    Text("Logout")
                }
            }
        }
        .navigationTitle("Profile")
    }
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            KBLog.auth.info("Logout OK")
            coordinator.resetToRoot()
        } catch {
            KBLog.auth.error("Logout failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
