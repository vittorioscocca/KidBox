//
//  HomeView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import FirebaseAuth
import SwiftUI
import OSLog

struct HomeView: View {
    var body: some View {
        VStack {
            Text("Home")
            Button("Logout") {
                do {
                    try Auth.auth().signOut()
                    KBLog.auth.info("Firebase sign-out OK")
                } catch {
                    KBLog.auth.error("Sign-out failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
}
