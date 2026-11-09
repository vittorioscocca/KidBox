//
//  KeyHandoff.swift
//  KidBox
//
//  Passaggio della chiave col QR (piano v2, sezione 3.2), gemello di
//  `keyHandoff.js` (web) e `KeyHandoff.kt` (Android).
//
//  Chi RICEVE (browser con «Entra con il telefono», dispositivo nuovo,
//  familiare senza chiave) crea `keyHandoffs/{roomId}` con la pubblica di una
//  coppia ECDH P-256 effimera e mostra il QR `KBKEY1.{roomId}.{pub}`.
//  Chi MANDA inquadra, usa la pubblica DEL QR (il server non può scambiarla),
//  e deposita in `payload` la chiave chiusa: AES-GCM con chiave
//  HKDF-SHA256(ECDH, salt = roomId, info = "kidbox-vault-v2:handoff"), AAD
//  "kidbox-vault-v2:handoff:{roomId}:{kind}:{familyId}".
//  `kind` = "rk" (stesso utente: la chiave personale) o "familyKey" (da un
//  familiare: la chiave di quella famiglia). Le rules lo impongono.
//

import Foundation
import CryptoKit
import FirebaseFirestore

enum KeyHandoff {

    static let prefix = "KBKEY1"
    static let info = "kidbox-vault-v2:handoff"
    static let ttl: TimeInterval = 10 * 60

    private static var db: Firestore { Firestore.firestore() }

    enum HandoffError: Error { case badQR, expired, mismatch, nothingToSend, openFailed }

    static func aad(roomId: String, kind: String, familyId: String?) -> String {
        "\(info):\(roomId):\(kind):\(familyId ?? "")"
    }

    static func wrapKey(shared: SharedSecret, roomId: String) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(roomId.utf8),
                                       sharedInfo: Data(info.utf8), outputByteCount: 32)
    }

    // MARK: chi manda

    struct Target {
        enum Kind { case rk, familyKey(familyId: String, familyName: String) }
        let roomId: String
        let pub: Data
        let kind: Kind
        /// «Chrome · Windows» per lo stesso utente, il nome del familiare altrimenti.
        let receiver: String
    }

    static func parse(_ text: String) -> (roomId: String, pub: Data)? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3, parts[0] == prefix,
              parts[1].count >= 20,
              let pub = FamilyKeyVaultCrypto.fromBase64Url(String(parts[2])), pub.count == 65 else { return nil }
        return (String(parts[1]), pub)
    }

    /// Legge la stanza e decide cosa mandare: la RK se è dello stesso utente e
    /// questo dispositivo la ha; altrimenti la chiave di una famiglia in comune.
    static func prepare(qr: String, uid: String, familyIds: [String]) async throws -> Target {
        guard let (roomId, pub) = parse(qr) else { throw HandoffError.badQR }
        let snap = try await db.collection("keyHandoffs").document(roomId).getDocument(source: .server)
        guard let d = snap.data(), d["payload"] == nil,
              let exp = (d["expiresAt"] as? Timestamp)?.dateValue(), exp > Date() else { throw HandoffError.expired }
        guard let roomUid = d["uid"] as? String,
              (d["pub"] as? String).flatMap(FamilyKeyVaultCrypto.fromBase64Url) == pub else { throw HandoffError.mismatch }
        let label = (d["label"] as? String) ?? ""

        if roomUid == uid, FamilyKeyVault.loadRK(uid: uid) != nil {
            return Target(roomId: roomId, pub: pub, kind: .rk, receiver: label)
        }
        for fid in Set(familyIds) where !fid.isEmpty {
            guard FamilyKeychainStore.loadFamilyKey(familyId: fid, userId: uid) != nil else { continue }
            let m = try? await db.collection("families").document(fid).collection("members")
                .document(roomUid).getDocument(source: .server).data()
            guard let m, m["role"] != nil, (m["isDeleted"] as? Bool) != true else { continue }
            let fam = try? await db.collection("families").document(fid).getDocument().data()
            let name = (fam?["name"] as? String) ?? ""
            let who = roomUid == uid ? label : ((m["displayName"] as? String) ?? (m["name"] as? String) ?? label)
            return Target(roomId: roomId, pub: pub, kind: .familyKey(familyId: fid, familyName: name), receiver: who)
        }
        throw HandoffError.nothingToSend
    }

    /// Chiude la chiave per la pubblica del QR e la deposita nella stanza.
    static func deliver(_ t: Target, uid: String) async throws {
        let kind: String
        let familyId: String?
        var plain: Data
        switch t.kind {
        case .rk:
            guard let rk = FamilyKeyVault.loadRK(uid: uid) else { throw HandoffError.nothingToSend }
            (kind, familyId, plain) = ("rk", nil, rk)
        case .familyKey(let fid, _):
            guard let key = FamilyKeychainStore.loadFamilyKey(familyId: fid, userId: uid) else { throw HandoffError.nothingToSend }
            (kind, familyId, plain) = ("familyKey", fid, key.withUnsafeBytes { Data($0) })
        }
        defer { plain.resetBytes(in: 0..<plain.count) }
        let eph = P256.KeyAgreement.PrivateKey()
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: t.pub)
        let shared = try eph.sharedSecretFromKeyAgreement(with: peer)
        let s = try FamilyKeyVaultCrypto.seal(plain, key: wrapKey(shared: shared, roomId: t.roomId),
                                              aad: aad(roomId: t.roomId, kind: kind, familyId: familyId))
        var payload: [String: Any] = [
            "kind": kind,
            "epk": FamilyKeyVaultCrypto.base64Url(eph.publicKey.x963Representation),
            "nonce": s.nonce, "cipher": s.cipher, "tag": s.tag,
        ]
        if let familyId { payload["familyId"] = familyId }
        try await db.collection("keyHandoffs").document(t.roomId).updateData([
            "payload": payload, "senderUid": uid, "sentAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: chi riceve

    struct Received { let kind: String; let familyId: String?; let bytes: Data }

    /// Una stanza aperta: il testo del QR, la scadenza, e `close()` che la cancella.
    final class Room {
        let roomId: String
        let qrText: String
        let expiresAt: Date
        private let priv: P256.KeyAgreement.PrivateKey
        private var listener: ListenerRegistration?
        private var done = false

        fileprivate init(roomId: String, priv: P256.KeyAgreement.PrivateKey, expiresAt: Date) {
            self.roomId = roomId
            self.priv = priv
            self.expiresAt = expiresAt
            qrText = "\(KeyHandoff.prefix).\(roomId).\(FamilyKeyVaultCrypto.base64Url(priv.publicKey.x963Representation))"
        }

        fileprivate func listen(onResult: @escaping @MainActor (Result<Received, Error>) -> Void) {
            listener = Firestore.firestore().collection("keyHandoffs").document(roomId)
                .addSnapshotListener { [weak self] snap, _ in
                    guard let self, !self.done, let p = snap?.data()?["payload"] as? [String: Any] else { return }
                    self.done = true
                    let result = Result<Received, Error> { try self.open(p) }
                    self.close()
                    Task { @MainActor in onResult(result) }
                }
        }

        private func open(_ p: [String: Any]) throws -> Received {
            guard let kind = p["kind"] as? String, let epkS = p["epk"] as? String,
                  let epk = FamilyKeyVaultCrypto.fromBase64Url(epkS),
                  let c = p["cipher"] as? String, let n = p["nonce"] as? String, let t = p["tag"] as? String
            else { throw HandoffError.openFailed }
            let familyId = p["familyId"] as? String
            let shared = try priv.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: epk))
            guard let bytes = try? FamilyKeyVaultCrypto.open(
                .init(cipher: c, nonce: n, tag: t),
                key: KeyHandoff.wrapKey(shared: shared, roomId: roomId),
                aad: KeyHandoff.aad(roomId: roomId, kind: kind, familyId: familyId)
            ), bytes.count == 32 else { throw HandoffError.openFailed }
            return Received(kind: kind, familyId: familyId, bytes: bytes)
        }

        func close() {
            listener?.remove()
            listener = nil
            Firestore.firestore().collection("keyHandoffs").document(roomId).delete { _ in }
        }
    }

    static func openRoom(uid: String, label: String,
                         onResult: @escaping @MainActor (Result<Received, Error>) -> Void) async throws -> Room {
        var idBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, idBytes.count, &idBytes)
        let roomId = FamilyKeyVaultCrypto.base64Url(Data(idBytes))
        let room = Room(roomId: roomId, priv: P256.KeyAgreement.PrivateKey(), expiresAt: Date().addingTimeInterval(ttl))
        try await db.collection("keyHandoffs").document(roomId).setData([
            "uid": uid,
            "pub": String(room.qrText.split(separator: ".")[2]),
            "label": String(label.prefix(80)),
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: room.expiresAt),
        ])
        room.listen(onResult: onResult)
        return room
    }

    /// Cosa fare di quello che è arrivato: la RK (se è quella della cassaforte)
    /// o la chiave di una famiglia, salvata come all'ingresso con invito.
    static func adopt(_ r: Received, uid: String) async throws {
        switch r.kind {
        case "rk":
            let slots = try await FamilyKeyVault.listSlots(uid: uid)
            let expected = try await db.collection("users").document(uid).collection("keyVault")
                .document(slots.first?.id ?? "recoveryCode").getDocument(source: .server).data()?["rkId"] as? String
            guard let expected, FamilyKeyVaultCrypto.rkId(r.bytes) == expected else { throw HandoffError.mismatch }
            try FamilyKeyVault.saveRK(r.bytes, uid: uid)
        case "familyKey":
            guard let fid = r.familyId else { throw HandoffError.openFailed }
            let key = SymmetricKey(data: r.bytes)
            try FamilyKeychainStore.saveFamilyKey(key, familyId: fid, userId: uid)
            await FamilyKeyEscrowService.backup(key: key, familyId: fid, userId: uid)
        default:
            throw HandoffError.openFailed
        }
    }
}
