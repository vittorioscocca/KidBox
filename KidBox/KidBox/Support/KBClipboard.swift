//
//  KBClipboard.swift
//  KidBox
//
//  Copia negli appunti con opzione solo-app e scadenza best-effort.
//

import UIKit
import UniformTypeIdentifiers

enum KBClipboard {

    /// Copia testo in `UIPasteboard`.
    /// - Parameters:
    ///   - expiresIn: dopo questo intervallo, se il contenuto del pasteboard coincide ancora con `string`, viene svuotato (best effort).
    ///   - localOnly: se `true`, usa `setItems` con opzione locale (stesso team / limitazioni incrociate come da API Apple).
    @MainActor
    static func copy(_ string: String, expiresIn: TimeInterval, localOnly: Bool) {
        let pb = UIPasteboard.general
        #if targetEnvironment(macCatalyst)
        // Su Mac Catalyst l'opzione `localOnly` con `setItems` non viene
        // propagata in modo affidabile alla pasteboard di sistema (NSPasteboard),
        // quindi l'incolla non funziona. Scriviamo direttamente la stringa.
        pb.string = string
        #else
        if localOnly {
            pb.setItems(
                [[UTType.plainText.identifier: string]],
                options: [UIPasteboard.OptionsKey.localOnly: true]
            )
        } else {
            pb.string = string
        }
        #endif
        let snapshot = string
        DispatchQueue.main.asyncAfter(deadline: .now() + expiresIn) {
            if pb.string == snapshot {
                pb.items = []
            }
        }
    }
}
