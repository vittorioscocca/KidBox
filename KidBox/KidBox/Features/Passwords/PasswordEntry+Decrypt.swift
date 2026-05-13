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
