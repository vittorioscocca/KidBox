//
//  HeroImageCache.swift
//  KidBox
//
//  Cache su disco della foto di famiglia, versionata sul timestamp remoto.
//
//  Prima la hero veniva riscaricata a ogni comparsa della Home: la card è
//  ricreata da `.id(heroPhotoUpdatedAt)` e il loader partiva sempre con
//  `image = nil`, quindi placeholder che lampeggia e un download completo ogni
//  volta. `URLCache.shared` non aiutava, perché gli oggetti su Firebase Storage
//  sono serviti senza `Cache-Control` utile (l'upload imposta solo il
//  `contentType`).
//
//  Qui la versione la decide `heroPhotoUpdatedAt` del documento famiglia: se il
//  file in cache è stato salvato con lo stesso timestamp del remoto, si usa
//  quello e non si tocca la rete. Se il remoto è più recente, si scarica e si
//  sostituisce.
//

import Foundation
import CryptoKit
import UIKit

enum HeroImageCache {

    /// Cartella dedicata dentro Caches: contenuto rigenerabile, quindi il
    /// sistema può recuperarne lo spazio sotto pressione senza rompere nulla.
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("hero-photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Identifica la foto ignorando la query string.
    ///
    /// L'URL di download Firebase porta un token che può cambiare a ogni
    /// riscrittura del file: tenerlo dentro la chiave farebbe scadere la cache
    /// anche quando l'immagine è identica. Il path invece è stabile
    /// (`.../families%2F{familyId}%2Fhero%2Fhero.jpg`).
    private static func key(for url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.query = nil
        let stable = comps?.string ?? url.absoluteString
        let digest = SHA256.hash(data: Data(stable.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// Timestamp come intero: entra nel nome del file, così la versione è
    /// leggibile senza aprire nulla e il confronto è una sola `fileExists`.
    private static func fileURL(for url: URL, updatedAt: Date) -> URL? {
        guard let directory else { return nil }
        let stamp = Int(updatedAt.timeIntervalSince1970)
        return directory.appendingPathComponent("\(key(for: url))-\(stamp).jpg")
    }

    // MARK: - Lettura

    /// Immagine in cache **solo se** combacia con la versione remota richiesta.
    ///
    /// - Parameter updatedAt: `heroPhotoUpdatedAt` della famiglia. Se è `nil`
    ///   non si può stabilire quale versione sia in cache, quindi si restituisce
    ///   `nil` e il chiamante scarica: meglio un download di troppo che una foto
    ///   vecchia mostrata per sempre.
    static func image(for url: URL, updatedAt: Date?) -> UIImage? {
        guard let updatedAt, let file = fileURL(for: url, updatedAt: updatedAt) else { return nil }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Scrittura

    /// Salva i byte scaricati come versione `updatedAt` e rimuove le precedenti.
    ///
    /// Non salva nulla se `updatedAt` è `nil`: senza versione il file non
    /// sarebbe mai riconosciuto come valido in lettura, resterebbe solo a
    /// occupare spazio.
    static func store(_ data: Data, for url: URL, updatedAt: Date?) {
        guard let updatedAt, let file = fileURL(for: url, updatedAt: updatedAt) else { return }
        do {
            try data.write(to: file, options: .atomic)
            removeStaleVersions(for: url, keeping: file)
        } catch {
            KBLog.persistence.kbError("HeroImageCache store failed: \(error.localizedDescription)")
        }
    }

    /// Elimina le versioni precedenti della stessa foto.
    ///
    /// Senza questo la cartella crescerebbe a ogni cambio foto o ritaglio, e
    /// niente ripulirebbe mai i file vecchi.
    private static func removeStaleVersions(for url: URL, keeping current: URL) {
        guard let directory else { return }
        let prefix = key(for: url) + "-"
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files
        where file.lastPathComponent.hasPrefix(prefix) && file.lastPathComponent != current.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
