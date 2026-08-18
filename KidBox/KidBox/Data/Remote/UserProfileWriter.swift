//
//  UserProfileWriter.swift
//  KidBox
//
//  Scrittura di nome/cognome fuori dalla schermata Profilo.
//
//  Serve al wizard di onboarding, che raccoglie nome e cognome prima che la
//  famiglia esista. La pipeline è la stessa di `ProfileView.saveProfile()`
//  limitatamente ai campi anagrafici — SwiftData, `users/{uid}`, App Group e
//  notifica — perché quella è UI-coupled (avatar, indirizzo, alert, stato
//  dirty) e non riutilizzabile così com'è.
//
//  La propagazione del nome al documento membro è separata
//  ([propagateDisplayNameToMember]) perché nel wizard la famiglia non esiste
//  ancora quando il nome viene inserito: va richiamata dopo la creazione o il
//  join, altrimenti il membro resta senza `displayName` per gli altri.
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore

enum UserProfileWriter {

    private static let appGroupSuite = "group.it.vittorioscocca.kidbox"

    /// Nome mostrato quando l'anagrafica è vuota. Stesso sentinella usato da
    /// `ProfileView` e `UserProfileRemoteSync`: va trattato come "non impostato".
    private static let placeholderName = "Utente"

    // MARK: - Anagrafica

    /// Salva nome e cognome su SwiftData e su `users/{uid}`, poi allinea
    /// App Group e schermate in ascolto.
    ///
    /// - Throws: se manca l'utente autenticato, se il salvataggio SwiftData
    ///   fallisce o se la scrittura su Firestore fallisce. Il chiamante deve
    ///   mostrare l'errore: un nome perso in silenzio è esattamente il tipo di
    ///   fallimento che l'utente non può diagnosticare.
    @MainActor
    static func saveNames(
        firstName: String,
        lastName: String,
        modelContext: ModelContext
    ) async throws {
        guard let user = Auth.auth().currentUser else {
            KBLog.auth.kbError("UserProfileWriter.saveNames: not authenticated")
            throw NSError(
                domain: "KidBox.Profile",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Utente non autenticato."]
            )
        }

        let uid = user.uid
        let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = full.isEmpty ? placeholderName : full

        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        let profile: KBUserProfile
        if let existing = try modelContext.fetch(desc).first {
            profile = existing
        } else {
            profile = KBUserProfile(uid: uid)
            modelContext.insert(profile)
        }

        let authEmail = (user.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !authEmail.isEmpty { profile.email = authEmail }
        profile.firstName   = fn
        profile.lastName    = ln
        profile.displayName = displayName
        profile.lastLoginAt = user.metadata.lastSignInDate ?? profile.lastLoginAt
        profile.updatedAt   = Date()

        try modelContext.save()
        KBLog.auth.kbInfo("UserProfileWriter: names saved locally uid=\(uid)")

        try await Firestore.firestore()
            .collection("users").document(uid)
            .setData([
                "firstName":   fn,
                "lastName":    ln,
                "displayName": displayName,
                "email":       profile.email ?? "",
                "updatedAt":   Timestamp(date: Date())
            ], merge: true)
        KBLog.app.kbDebug("UserProfileWriter: saved to users/\(uid)")

        guard displayName != placeholderName else { return }

        UserDefaults(suiteName: appGroupSuite)?
            .set(displayName, forKey: "currentUserDisplayName")

        NotificationCenter.default.post(
            name: .kbProfileDisplayNameUpdated,
            object: nil,
            userInfo: ["displayName": displayName]
        )
    }

    // MARK: - Propagazione al membro famiglia

    /// Scrive il `displayName` corrente su `families/{familyId}/members/{uid}`
    /// e sul membro locale.
    ///
    /// Best effort: un errore qui non deve far fallire creazione o join della
    /// famiglia, che a quel punto sono già andati a buon fine. Se il profilo
    /// non ha ancora un nome reale non fa nulla.
    @MainActor
    static func propagateDisplayNameToMember(
        familyId: String,
        modelContext: ModelContext
    ) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty, !familyId.isEmpty else { return }

        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        let name = (try? modelContext.fetch(desc).first?.displayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name != placeholderName else {
            KBLog.app.kbDebug("UserProfileWriter: no display name to propagate familyId=\(familyId)")
            return
        }

        do {
            try await Firestore.firestore()
                .collection("families").document(familyId)
                .collection("members").document(uid)
                .setData(["displayName": name, "updatedAt": Timestamp(date: Date())], merge: true)
            KBLog.app.kbInfo("UserProfileWriter: member display name propagated familyId=\(familyId)")
        } catch {
            KBLog.app.kbError(
                "UserProfileWriter: member name propagation failed familyId=\(familyId) err=\(error.localizedDescription)"
            )
        }

        let memberDesc = FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.userId == uid && $0.familyId == familyId }
        )
        if let member = try? modelContext.fetch(memberDesc).first, member.displayName != name {
            member.displayName = name
            member.updatedAt = Date()
            try? modelContext.save()
        }
    }
}
