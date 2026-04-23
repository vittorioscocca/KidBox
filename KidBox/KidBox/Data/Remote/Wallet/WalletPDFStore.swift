//
//  WalletPDFStore.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import FirebaseAuth
import FirebaseStorage
import OSLog

/// Errori del `WalletPDFStore`.
enum WalletPDFStoreError: Error {
    case notAuthenticated
    case invalidData
    case downloadFailed
    case uploadTimeout
}

/// Salvataggio/scaricamento del PDF di un biglietto Wallet su Firebase Storage.
///
/// Convenzione path:
/// `families/{familyId}/wallet/{ticketId}/ticket.pdf.kbenc`
///
/// Il PDF è cifrato con `WalletCryptoService.encryptPDF` (AES-GCM combined
/// con la chiave per-famiglia). Il content-type su Storage è
/// `application/octet-stream` perché lato server è opaco — solo il client
/// con la chiave Keychain può ricostruire il PDF originale.
final class WalletPDFStore {

    private let storage = Storage.storage()

    // MARK: - Path helpers

    private func storagePath(familyId: String, ticketId: String) -> String {
        "families/\(familyId)/wallet/\(ticketId)/ticket.pdf.kbenc"
    }

    // MARK: - Upload

    /// Cifra il PDF e lo carica su Storage.
    /// - Returns: `(storagePath, downloadURL, encryptedBytes)`. L'URL va salvato in
    ///   `KBWalletTicket.pdfStorageURL`, lo storagePath è derivabile dai due id.
    func upload(
        familyId: String,
        ticketId: String,
        originalFileName: String,
        pdfData: Data
    ) async throws -> (storagePath: String, downloadURL: String, encryptedBytes: Int64) {
        KBLog.sync.kbInfo("[WalletPDF] upload start familyId=\(familyId) ticketId=\(ticketId) bytes=\(pdfData.count)")

        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[WalletPDF] upload failed: not authenticated")
            throw WalletPDFStoreError.notAuthenticated
        }

        guard !pdfData.isEmpty else {
            KBLog.sync.kbError("[WalletPDF] upload failed: empty pdfData")
            throw WalletPDFStoreError.invalidData
        }

        let encrypted = try WalletCryptoService.encryptPDF(pdfData, familyId: familyId, userId: uid)

        let path = storagePath(familyId: familyId, ticketId: ticketId)
        let ref = storage.reference(withPath: path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = [
            "kb_encrypted": "1",
            "kb_alg": "AES-GCM",
            "kb_orig_mime": "application/pdf",
            "kb_orig_name": originalFileName.isEmpty ? "ticket.pdf" : originalFileName,
            "kb_module": "wallet"
        ]

        KBLog.sync.kbInfo("[WalletPDF] upload putData start path=\(path) encBytes=\(encrypted.count)")

        // Usiamo putData (non putDataAsync) per poter osservare progress e
        // failure in streaming: se le Storage Rules negano la scrittura,
        // l'errore è immediato e visibile nei log (non silenzioso).
        //
        // NB su thread-safety: gli observer di FirebaseStorage firano sulla
        // main queue; il Task del timeout gira sulla cooperative pool. Per
        // evitare una race sul flag `didResume` (che farebbe crashare la
        // CheckedContinuation con "resumed twice"), serializziamo tutte le
        // chiamate a `resumeOnce` sulla main queue.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Wrapper reference-type così il flag è condiviso tra closure
            // senza copy-on-write semantics.
            final class ResumeGate { var didResume = false }
            let gate = ResumeGate()

            let resumeOnce: (Result<Void, Error>) -> Void = { result in
                // Tutte le resume passano da main → ordine seriale garantito.
                let apply = {
                    guard !gate.didResume else { return }
                    gate.didResume = true
                    switch result {
                    case .success: cont.resume()
                    case .failure(let err): cont.resume(throwing: err)
                    }
                }
                if Thread.isMainThread {
                    apply()
                } else {
                    DispatchQueue.main.async(execute: apply)
                }
            }

            let task = ref.putData(encrypted, metadata: metadata)

            task.observe(.progress) { snapshot in
                if let p = snapshot.progress {
                    let pct = Int((Double(p.completedUnitCount) / Double(max(p.totalUnitCount, 1))) * 100)
                    KBLog.sync.kbDebug("[WalletPDF] upload progress ticketId=\(ticketId) \(pct)%")
                }
            }

            task.observe(.success) { _ in
                KBLog.sync.kbInfo("[WalletPDF] upload putData success ticketId=\(ticketId)")
                resumeOnce(.success(()))
            }

            task.observe(.failure) { snapshot in
                let err = snapshot.error ?? NSError(domain: "WalletPDFStore", code: -1)
                let ns = err as NSError
                KBLog.sync.kbError("[WalletPDF] upload FAILURE ticketId=\(ticketId) domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) userInfo=\(ns.userInfo)")
                resumeOnce(.failure(err))
            }

            // Timeout di sicurezza: se putData non ritorna né success né
            // failure entro 90s (tipico sintomo di rules-in-attesa o retry
            // silenzioso), interrompiamo e restituiamo uploadTimeout.
            Task {
                try? await Task.sleep(nanoseconds: 90 * 1_000_000_000)
                // La check-and-resume è serializzata sulla main queue dentro
                // resumeOnce, quindi qui non serve leggere didResume.
                KBLog.sync.kbDebug("[WalletPDF] upload watchdog fired ticketId=\(ticketId)")
                await MainActor.run {
                    guard !gate.didResume else { return }
                    KBLog.sync.kbError("[WalletPDF] upload TIMEOUT ticketId=\(ticketId) — cancelling task")
                    task.cancel()
                }
                resumeOnce(.failure(WalletPDFStoreError.uploadTimeout))
            }
        }

        let url = try await ref.downloadURL()

        KBLog.sync.kbInfo("[WalletPDF] upload OK ticketId=\(ticketId) url=\(url.absoluteString)")
        return (storagePath: path, downloadURL: url.absoluteString, encryptedBytes: Int64(encrypted.count))
    }

    // MARK: - Download

    /// Scarica e decifra il PDF di un biglietto, restituendo i bytes in chiaro.
    /// Usata da `WalletTicketDetailView` quando l'utente apre il viewer.
    func download(
        familyId: String,
        ticketId: String,
        maxBytes: Int64 = 25 * 1024 * 1024
    ) async throws -> Data {
        KBLog.sync.kbInfo("[WalletPDF] download start familyId=\(familyId) ticketId=\(ticketId)")

        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[WalletPDF] download failed: not authenticated")
            throw WalletPDFStoreError.notAuthenticated
        }

        let ref = storage.reference(withPath: storagePath(familyId: familyId, ticketId: ticketId))

        let encrypted: Data = try await withCheckedThrowingContinuation { cont in
            ref.getData(maxSize: maxBytes) { data, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: WalletPDFStoreError.downloadFailed)
                }
            }
        }

        let pdf = try WalletCryptoService.decryptPDF(encrypted, familyId: familyId, userId: uid)
        KBLog.sync.kbInfo("[WalletPDF] download OK ticketId=\(ticketId) bytes=\(pdf.count)")
        return pdf
    }

    // MARK: - Delete

    /// Elimina il PDF di un biglietto. Idempotente: ignora "object not found".
    func delete(familyId: String, ticketId: String) async throws {
        let path = storagePath(familyId: familyId, ticketId: ticketId)
        KBLog.sync.kbInfo("[WalletPDF] delete familyId=\(familyId) ticketId=\(ticketId)")

        do {
            try await storage.reference(withPath: path).delete()
        } catch {
            // StorageErrorCode.objectNotFound = -13010 — già rimosso, no-op
            let ns = error as NSError
            if ns.domain == StorageErrorDomain && ns.code == StorageErrorCode.objectNotFound.rawValue {
                KBLog.sync.kbDebug("[WalletPDF] delete: already gone, ignored")
                return
            }
            throw error
        }
    }
}
