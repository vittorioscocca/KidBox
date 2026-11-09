//
//  FamilyKeyVault.swift
//  KidBox
//
//  Cassaforte della chiave di famiglia, v2 (piano in
//  `internal/cifratura-chiave-di-riserva-v2.md`, sezione 3.3).
//
//    segreto (codice di recupero / passkey)
//        └─ apre ─▶ chiave personale RK (32 byte, una per utente)
//                       └─ apre ─▶ chiave di famiglia A, B, …
//
//  - La RK vive nel Portachiavi sincronizzato (account `kidbox.vault.rk.{uid}`).
//  - Gli slot stanno in `users/{uid}/keyVault/{recoveryCode | passkey_<id>}`.
//  - La copia v2 sta nella mappa `v2` di `families/{fid}/memberKeyBackups/{uid}`,
//    ACCANTO ai campi della v1, che resta fino alla Fase 3.
//
//  ⚠️ Le costanti di `FamilyKeyVaultCrypto` sono identiche al web
//  (`familyKeyVault.js`) e ad Android (`FamilyKeyVault.kt`): un carattere
//  diverso = chiave diversa = dati illeggibili, senza un errore. I test in
//  `KidBoxTests/CryptoTests/FamilyKeyVaultTests.swift` aprono un vettore
//  scritto davvero dalla web app.
//
//  Fase 1: lettura e scrittura. La RK nasce SOLO con la cassaforte (codice
//  creato o aperto): una RK nata in silenzio sul telefono, mentre un altro
//  dispositivo ne crea un'altra, darebbe due chiavi personali per lo stesso
//  utente. Le schermate per creare o aprire la cassaforte sono la Fase 2.
//

import Foundation
import CryptoKit
import Security
import FirebaseFirestore

// MARK: - Primitive (pure, testate sui vettori del web)

enum FamilyKeyVaultCrypto {

    static let context = "kidbox-vault-v2"
    static let version = 2
    static let infoSlotRecovery = "kidbox-vault-v2:slot:recoveryCode"
    static let infoSlotPasskey = "kidbox-vault-v2:slot:passkey"
    static let infoRkId = "kidbox-vault-v2:rk-id"
    static let infoFamily = "kidbox-vault-v2:family"
    static let aadSlotPrefix = "kidbox-vault-v2:rk:"         // + uid
    static let aadFamilyPrefix = "kidbox-vault-v2:family:"   // + uid + ":" + familyId
    static let prfInput = "kidbox-vault-v2:prf"
    /// Base32 di Crockford: niente I, L, O, U. 24 caratteri = 120 bit.
    static let codeAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let codeLength = 24

    enum VaultError: Error { case wrongSecret, malformed }

    struct Sealed: Equatable {
        let cipher: String  // base64
        let nonce: String   // base64
        let tag: String     // base64
    }

    // MARK: codice di recupero

    /// 15 byte casuali → 24 caratteri, mostrati `XXXX-XXXX-…`.
    static func generateRecoveryCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 15)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        var out = ""
        var value: UInt32 = 0
        var bits = 0
        for b in bytes {
            value = (value << 8) | UInt32(b)
            bits += 8
            while bits >= 5 {
                out.append(codeAlphabet[Int((value >> UInt32(bits - 5)) & 31)])
                bits -= 5
            }
            value &= (1 << UInt32(bits)) - 1
        }
        return formatRecoveryCode(out)
    }

    /// Forma canonica: maiuscole, senza spazi né trattini, O→0, I/L→1. `nil` se non valido.
    static func normalizeRecoveryCode(_ input: String) -> String? {
        var s = input.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        s = s.replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
        guard s.count == codeLength, s.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return s
    }

    static func formatRecoveryCode(_ canonical: String) -> String {
        stride(from: 0, to: canonical.count, by: 4).map { i -> String in
            let start = canonical.index(canonical.startIndex, offsetBy: i)
            let end = canonical.index(start, offsetBy: min(4, canonical.count - i))
            return String(canonical[start..<end])
        }.joined(separator: "-")
    }

    // MARK: derivazioni

    static func hkdf(_ ikm: Data, salt: Data, info: String, count: Int = 32) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: count
        )
    }

    /// Identificativo pubblico della RK (base64url, 16 byte).
    static func rkId(_ rk: Data) -> String {
        hkdf(rk, salt: Data(), info: infoRkId, count: 16).withUnsafeBytes { base64Url(Data($0)) }
    }

    static func slotKey(type: String, ikm: Data, salt: Data) -> SymmetricKey {
        hkdf(ikm, salt: salt, info: type == "recoveryCode" ? infoSlotRecovery : infoSlotPasskey)
    }

    static func familyWrapKey(_ rk: Data) -> SymmetricKey {
        hkdf(rk, salt: Data(), info: infoFamily)
    }

    // MARK: AES-GCM con AAD, ciphertext e tag separati

    static func seal(_ plain: Data, key: SymmetricKey, aad: String) throws -> Sealed {
        let box = try AES.GCM.seal(plain, using: key, nonce: AES.GCM.Nonce(), authenticating: Data(aad.utf8))
        return Sealed(
            cipher: box.ciphertext.base64EncodedString(),
            nonce: Data(box.nonce).base64EncodedString(),
            tag: box.tag.base64EncodedString()
        )
    }

    static func open(_ s: Sealed, key: SymmetricKey, aad: String) throws -> Data {
        guard let c = Data(base64Encoded: s.cipher),
              let n = Data(base64Encoded: s.nonce),
              let t = Data(base64Encoded: s.tag) else { throw VaultError.malformed }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: n), ciphertext: c, tag: t)
        return try AES.GCM.open(box, using: key, authenticating: Data(aad.utf8))
    }

    // MARK: slot e copia v2

    /// Apre uno slot del codice: restituisce la RK o `wrongSecret`.
    static func openRecoverySlot(uid: String, code: String, salt: String, sealed: Sealed, rkId expected: String?) throws -> Data {
        guard let canonical = normalizeRecoveryCode(code), let saltData = Data(base64Encoded: salt) else {
            throw VaultError.wrongSecret
        }
        let key = slotKey(type: "recoveryCode", ikm: Data(canonical.utf8), salt: saltData)
        guard let rk = try? open(sealed, key: key, aad: aadSlotPrefix + uid), rk.count == 32 else {
            throw VaultError.wrongSecret
        }
        if let expected, rkId(rk) != expected { throw VaultError.wrongSecret }
        return rk
    }

    static func sealRecoverySlot(uid: String, code: String, rk: Data) throws -> (salt: String, sealed: Sealed) {
        guard let canonical = normalizeRecoveryCode(code) else { throw VaultError.wrongSecret }
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let key = slotKey(type: "recoveryCode", ikm: Data(canonical.utf8), salt: Data(salt))
        return (Data(salt).base64EncodedString(), try seal(rk, key: key, aad: aadSlotPrefix + uid))
    }

    static func sealFamilyKeyV2(uid: String, familyId: String, familyKey: Data, rk: Data) throws -> Sealed {
        try seal(familyKey, key: familyWrapKey(rk), aad: "\(aadFamilyPrefix)\(uid):\(familyId)")
    }

    static func openFamilyKeyV2(uid: String, familyId: String, sealed: Sealed, rk: Data) -> Data? {
        guard let raw = try? open(sealed, key: familyWrapKey(rk), aad: "\(aadFamilyPrefix)\(uid):\(familyId)"),
              raw.count == 32 else { return nil }
        return raw
    }

    static func base64Url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Cassaforte: Portachiavi, Firestore, interruttore

enum FamilyKeyVault {

    private static let db = Firestore.firestore()
    private static let service = "KidBox"
    private static func account(_ uid: String) -> String { "kidbox.vault.rk.\(uid)" }

    // MARK: RK nel Portachiavi (sincronizzato con iCloud, come la chiave di famiglia)

    static func loadRK(uid: String) -> Data? {
        guard !uid.isEmpty else { return nil }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(uid),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, d.count == 32 else { return nil }
        return d
    }

    static func saveRK(_ rk: Data, uid: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(uid),
            kSecAttrSynchronizable as String: true,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = rk
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KidBox.Vault", code: Int(status))
        }
    }

    // MARK: interruttore `config/keyVault`

    struct Flags { let active: Bool; let enforce: Bool }
    private static var flagCache: (uid: String, at: Date, value: Flags)?

    /// `enabled` = tutti; `internal` = solo `config/internalUsers.uids`; `enforce`
    /// = niente «Più tardi». Spento o illeggibile = comportamento di prima.
    static func flags(uid: String) async -> Flags {
        if let c = flagCache, c.uid == uid, Date().timeIntervalSince(c.at) < 300 { return c.value }
        var value = Flags(active: false, enforce: false)
        do {
            async let cfg = db.collection("config").document("keyVault").getDocument()
            async let internalDoc = db.collection("config").document("internalUsers").getDocument()
            let c = try await cfg.data() ?? [:]
            let uids = (try await internalDoc.data()?["uids"] as? [String]) ?? []
            let active = (c["enabled"] as? Bool == true) || (uids.contains(uid) && c["internal"] as? Bool == true)
            value = Flags(active: active, enforce: active && c["enforce"] as? Bool == true)
        } catch {
            KBLog.security.kbInfo("Vault flags non leggibili: \(error.localizedDescription)")
        }
        flagCache = (uid, Date(), value)
        return value
    }

    // MARK: copia v2

    static func sealed(from map: [String: Any]?) -> (FamilyKeyVaultCrypto.Sealed, rkId: String)? {
        guard let m = map,
              let c = m["cipher"] as? String, let n = m["nonce"] as? String,
              let t = m["tag"] as? String, let id = m["rkId"] as? String else { return nil }
        return (.init(cipher: c, nonce: n, tag: t), id)
    }

    /// La chiave di famiglia dalla mappa `v2`, se questo dispositivo ha la RK giusta.
    static func openV2(uid: String, familyId: String, v2: [String: Any]?) -> SymmetricKey? {
        guard let (s, id) = sealed(from: v2), let rk = loadRK(uid: uid),
              FamilyKeyVaultCrypto.rkId(rk) == id,
              let raw = FamilyKeyVaultCrypto.openFamilyKeyV2(uid: uid, familyId: familyId, sealed: s, rk: rk)
        else { return nil }
        return SymmetricKey(data: raw)
    }

    /// Il blocco `v2` da mettere nel documento, o nil se manca la RK o la cassaforte è spenta.
    static func v2Field(uid: String, familyId: String, familyKey: SymmetricKey) async -> [String: Any]? {
        guard await flags(uid: uid).active, let rk = loadRK(uid: uid) else { return nil }
        let raw = familyKey.withUnsafeBytes { Data($0) }
        guard let s = try? FamilyKeyVaultCrypto.sealFamilyKeyV2(uid: uid, familyId: familyId, familyKey: raw, rk: rk)
        else { return nil }
        return [
            "cipher": s.cipher, "nonce": s.nonce, "tag": s.tag,
            "rkId": FamilyKeyVaultCrypto.rkId(rk),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }

    /// Scrive la copia v2 (merge: la v1 non si tocca) e la VERIFICA rileggendola
    /// dal server e aprendola (piano, 4 bis regola 4). Non cancella niente.
    @discardableResult
    static func writeAndVerifyV2(uid: String, familyId: String, familyKey: SymmetricKey) async -> Bool {
        guard let field = await v2Field(uid: uid, familyId: familyId, familyKey: familyKey) else { return false }
        let ref = db.collection("families").document(familyId).collection("memberKeyBackups").document(uid)
        do {
            try await ref.setData(["v2": field], merge: true)
            let fresh = try await ref.getDocument(source: .server)
            let reopened = openV2(uid: uid, familyId: familyId, v2: fresh.data()?["v2"] as? [String: Any])
            let ok = reopened?.withUnsafeBytes { Data($0) } == familyKey.withUnsafeBytes { Data($0) }
            if !ok { KBLog.security.kbError("Vault: copia v2 non verificata familyId=\(familyId)") }
            return ok
        } catch {
            KBLog.security.kbError("Vault: copia v2 non scritta familyId=\(familyId) err=\(error.localizedDescription)")
            return false
        }
    }

    // MARK: creare e aprire la cassaforte (le schermate sono la Fase 2)

    enum OpenError: Error { case exists, wrongSecret, missing }

    /// Crea la cassaforte col codice già mostrato e confermato. Se un altro
    /// dispositivo l'ha appena creata: `.exists`, e si apre quella.
    static func createVault(uid: String, recoveryCode: String) async throws {
        var rkBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, rkBytes.count, &rkBytes)
        let rk = Data(rkBytes)
        let (salt, s) = try FamilyKeyVaultCrypto.sealRecoverySlot(uid: uid, code: recoveryCode, rk: rk)
        let col = db.collection("users").document(uid).collection("keyVault")
        if !(try await col.getDocuments().isEmpty) { throw OpenError.exists }
        let ref = col.document("recoveryCode")
        let rec: [String: Any] = [
            "type": "recoveryCode", "version": FamilyKeyVaultCrypto.version,
            "rkId": FamilyKeyVaultCrypto.rkId(rk), "salt": salt,
            "nonce": s.nonce, "cipher": s.cipher, "tag": s.tag,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        _ = try await db.runTransaction { txn, errPtr in
            do {
                if try txn.getDocument(ref).exists {
                    errPtr?.pointee = NSError(domain: "KidBox.Vault", code: 409)
                    return nil
                }
            } catch let e as NSError { errPtr?.pointee = e; return nil }
            txn.setData(rec, forDocument: ref)
            return nil
        }
        try saveRK(rk, uid: uid)
    }

    /// Apre la cassaforte col codice di recupero e salva la RK nel Portachiavi.
    static func openWithRecoveryCode(uid: String, recoveryCode: String) async throws {
        let snap = try await db.collection("users").document(uid).collection("keyVault")
            .document("recoveryCode").getDocument()
        guard let d = snap.data(), let salt = d["salt"] as? String,
              let c = d["cipher"] as? String, let n = d["nonce"] as? String, let t = d["tag"] as? String
        else { throw OpenError.missing }
        let rk: Data
        do {
            rk = try FamilyKeyVaultCrypto.openRecoverySlot(
                uid: uid, code: recoveryCode, salt: salt,
                sealed: .init(cipher: c, nonce: n, tag: t), rkId: d["rkId"] as? String
            )
        } catch { throw OpenError.wrongSecret }
        try saveRK(rk, uid: uid)
    }
}
