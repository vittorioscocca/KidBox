//
//  ProfileView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import FirebaseAuth
import OSLog

/// User profile / account info screen.
///
/// Shows basic authentication state and allows the user to sign out.
///
/// - Important:
///   - Be careful with PII in UI/logs. UID is shown for debugging/support and is selectable.
///   - Logs avoid printing emails. Errors are logged with `.public` to help debugging.
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
                            .textSelection(.enabled)
                    }
                } else {
                    Text("Non autenticato")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    KBLog.auth.debug("Logout tap")
                    signOut()
                } label: {
                    Text("Logout")
                }
                .accessibilityLabel("Logout")
            }
        }
        .navigationTitle("Profilo")
        .onAppear {
            // View logs: keep them minimal to avoid spam in SwiftUI re-renders.
            let isAuthed = (Auth.auth().currentUser != nil)
            KBLog.auth.debug("ProfileView appeared authed=\(isAuthed, privacy: .public)")
        }
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
