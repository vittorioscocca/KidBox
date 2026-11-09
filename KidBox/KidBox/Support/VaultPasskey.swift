//
//  VaultPasskey.swift
//  KidBox
//
//  La cerimonia WebAuthn della cassaforte su iOS e Mac (piano v2, sezione
//  3.4): passkey di piattaforma con l'estensione PRF, RP ID `kidboxapp.com`
//  (Associated Domains `webcredentials:kidboxapp.com`, sezione `webcredentials`
//  dell'apple-app-site-association) e stesso input PRF del web e di Android.
//  Una passkey creata qui apre la cassaforte anche dal browser, e viceversa.
//
//  Restituisce solo (rawId, uscita PRF): la crittografia è in FamilyKeyVault.
//

import AuthenticationServices
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class VaultPasskey: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    static let rpId = "kidboxapp.com"

    enum PasskeyError: Error { case unsupported(String), cancelled }

    struct Result { let rawId: Data; let prf: Data }

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    private static var prfSalt: Data { Data(FamilyKeyVaultCrypto.prfInput.utf8) }

    private static func challenge() -> Data {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return Data(b)
    }

    private static func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// Crea una passkey per `uid` e ne ricava l'uscita PRF.
    static func create(uid: String, name: String) async throws -> Result {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let req = provider.createCredentialRegistrationRequest(challenge: challenge(), name: name, userID: Data(uid.utf8))
        req.userVerificationPreference = .required
        req.prf = .inputValues(.saltInput1(prfSalt))
        let auth = try await VaultPasskey().perform(req)
        guard let cred = auth.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw PasskeyError.unsupported("tipo")
        }
        if let out = cred.prf {
            if !out.isSupported { throw PasskeyError.unsupported("prf") }
            if let first = out.first { return Result(rawId: cred.credentialID, prf: bytes(first)) }
        }
        // Alcuni gestori dicono solo «supportato» alla creazione: l'uscita arriva con un'asserzione.
        return try await assert(allowIds: [cred.credentialID])
    }

    /// Asserzione con una delle passkey registrate: quale è stata usata e la sua uscita PRF.
    static func assert(allowIds: [Data]) async throws -> Result {
        guard !allowIds.isEmpty else { throw PasskeyError.unsupported("nessuna") }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let req = provider.createCredentialAssertionRequest(challenge: challenge())
        req.allowedCredentials = allowIds.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        req.userVerificationPreference = .required
        req.prf = .inputValues(.saltInput1(prfSalt))
        let auth = try await VaultPasskey().perform(req)
        guard let cred = auth.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion,
              let out = cred.prf else { throw PasskeyError.unsupported("prf") }
        let prf = bytes(out.first)
        guard prf.count >= 32 else { throw PasskeyError.unsupported("prf") }
        return Result(rawId: cred.credentialID, prf: prf)
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let c = ASAuthorizationController(authorizationRequests: [request])
            c.delegate = self
            c.presentationContextProvider = self
            controller = c
            c.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            continuation?.resume(returning: authorization)
            continuation = nil
            self.controller = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            if let e = error as? ASAuthorizationError, e.code == .canceled {
                continuation?.resume(throwing: PasskeyError.cancelled)
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
            self.controller = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
            #else
            return ASPresentationAnchor()
            #endif
        }
    }
}
