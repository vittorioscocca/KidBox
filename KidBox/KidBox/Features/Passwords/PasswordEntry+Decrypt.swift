//
//  PasswordEntry+Decrypt.swift
//  KidBox
//

import Foundation

extension PasswordEntry {

    func decryptTitle() throws -> String {
        try PasswordCypher.decrypt(titleCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }

    func decryptUsername() throws -> String? {
        guard let usernameCipher, !usernameCipher.isEmpty else { return nil }
        return try PasswordCypher.decrypt(usernameCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }

    func decryptPassword() throws -> String {
        try PasswordCypher.decrypt(passwordCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }

    func decryptWebsite() throws -> String? {
        guard let websiteCipher, !websiteCipher.isEmpty else { return nil }
        return try PasswordCypher.decrypt(websiteCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }

    func decryptNotes() throws -> String? {
        guard let notesCipher, !notesCipher.isEmpty else { return nil }
        return try PasswordCypher.decrypt(notesCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }

    func decryptOtpJson() throws -> String? {
        guard let otpConfigCipher, !otpConfigCipher.isEmpty else { return nil }
        return try PasswordCypher.decrypt(otpConfigCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }
}

extension PasswordGroup {

    func decryptName() throws -> String {
        try PasswordCypher.decrypt(nameCipher, familyId: familyId, visibility: visibility, createdBy: createdBy)
    }
}

// MARK: - Nome visualizzato dei gruppi

extension PasswordGroup {

    /// Nome da mostrare in UI.
    ///
    /// I gruppi seed vengono creati con il nome già tradotto nella lingua attiva
    /// al momento del seed e salvato cifrato su Firestore: una famiglia creata in
    /// italiano si porta dietro "Lavoro" anche se poi l'app passa in inglese.
    /// Qui lo slug si ricava dall'ID deterministico `kb.password.group.{familyId}.{slug}`
    /// e si rimostra il nome nella lingua corrente.
    ///
    /// L'utente però può rinominare anche i gruppi di sistema (`EditGroupSheet`),
    /// e `isSystem` resta `true`: tradurre alla cieca cancellerebbe la sua scelta.
    /// Quindi si traduce solo se il nome salvato è ancora **uno dei nomi seed
    /// noti** per quello slug — in una qualsiasi delle lingue dell'app. Se è
    /// stato cambiato in altro, vince quello che ha scritto l'utente.
    var displayName: String {
        let stored = (try? decryptName()) ?? ""
        guard isSystem, let seed = PasswordGroupsService.seedDefinition(forGroupId: id, familyId: familyId) else {
            return stored.isEmpty ? String(localized: "Gruppo") : stored
        }
        guard PasswordGroupsService.isUnrenamedSeedName(stored, key: seed.localizationKey) else { return stored }
        return PasswordGroupsService.localizedDefaultName(for: seed.localizationKey)
    }
}
