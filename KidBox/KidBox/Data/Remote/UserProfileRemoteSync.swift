//
//  UserProfileRemoteSync.swift
//  KidBox
//
//  Dopo login: allinea `KBUserProfile` (e i membri locali) con `users/{uid}` su Firestore,
//  così nome/cognome e display name sono coerenti senza aprire prima il Profilo.
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore

enum UserProfileRemoteSync {

    private static let appGroupSuite = "group.it.vittorioscocca.kidbox"

    /// Legge `users/{uid}` e aggiorna SwiftData + App Group + notifica per le schermate in ascolto.
    @MainActor
    static func mergeFirestoreUserIntoLocal(uid: String, modelContext: ModelContext) async {
        guard !uid.isEmpty else { return }

        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }

            let remoteFirst = (data["firstName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let remoteLast = (data["lastName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var remoteDisplay = (data["displayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if remoteDisplay.isEmpty {
                let full = "\(remoteFirst) \(remoteLast)".trimmingCharacters(in: .whitespacesAndNewlines)
                remoteDisplay = full
            }
            let remoteAddress = (data["familyAddress"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteEmail = ((data["email"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
            let existing = try? modelContext.fetch(desc).first
            let profile: KBUserProfile
            if let existing {
                profile = existing
            } else {
                profile = KBUserProfile(uid: uid, email: Auth.auth().currentUser?.email, displayName: Auth.auth().currentUser?.displayName)
                modelContext.insert(profile)
            }

            if !remoteFirst.isEmpty { profile.firstName = remoteFirst }
            if !remoteLast.isEmpty { profile.lastName = remoteLast }
            if let addr = remoteAddress, !addr.isEmpty { profile.familyAddress = addr }
            if !remoteEmail.isEmpty { profile.email = remoteEmail }

            if !remoteDisplay.isEmpty && remoteDisplay != "Utente" {
                profile.displayName = remoteDisplay
            }

            profile.updatedAt = Date()
            try modelContext.save()

            let canonical = resolvedCanonicalDisplayName(from: profile)
            if !canonical.isEmpty && canonical != "Utente" {
                syncLocalMembersDisplayName(uid: uid, name: canonical, modelContext: modelContext)

                let shared = UserDefaults(suiteName: appGroupSuite)
                shared?.set(canonical, forKey: "currentUserDisplayName")

                NotificationCenter.default.post(
                    name: .kbProfileDisplayNameUpdated,
                    object: nil,
                    userInfo: ["displayName": canonical]
                )
            }

            KBLog.data.kbDebug("UserProfileRemoteSync: merged users/\(uid)")
        } catch {
            KBLog.data.kbError("UserProfileRemoteSync: merge failed \(error.localizedDescription)")
        }
    }

    private static func resolvedCanonicalDisplayName(from profile: KBUserProfile) -> String {
        let dn = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !dn.isEmpty && dn != "Utente" { return dn }
        let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func syncLocalMembersDisplayName(uid: String, name: String, modelContext: ModelContext) {
        let desc = FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.userId == uid })
        guard let members = try? modelContext.fetch(desc) else { return }
        var changed = false
        for m in members where m.displayName != name {
            m.displayName = name
            m.updatedAt = Date()
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }
}
