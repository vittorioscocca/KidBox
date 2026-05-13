//
//  AutoFillSync.swift
//  KidBox
//
//  Sincronizza le identità QuickType con `ASCredentialIdentityStore` dopo ogni rebuild dello snapshot.
//

import AuthenticationServices
import Foundation

enum AutoFillSync {

    /// Aggiorna la barra QuickType; se l’utente non ha abilitato KidBox in Impostazioni → Password, è un no-op.
    static func replaceQuickTypeCredentials(with snapshot: AutoFillSnapshot) {
        ASCredentialIdentityStore.shared.getState { state in
            guard Self.isProviderEnabled(state) else { return }
            let identities: [ASPasswordCredentialIdentity] = snapshot.items.map { item in
                let hasWebsite = item.website.map { !$0.isEmpty } ?? false
                let identifier: String
                let type: ASCredentialServiceIdentifier.IdentifierType
                if hasWebsite, let host = item.website {
                    identifier = "https://\(host)/"
                    type = .URL
                } else {
                    identifier = item.title
                    type = .domain
                }
                let service = ASCredentialServiceIdentifier(identifier: identifier, type: type)
                return ASPasswordCredentialIdentity(serviceIdentifier: service, user: item.username, recordIdentifier: item.id)
            }
            ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities, completion: nil)
        }
    }

    static func clearQuickTypeCredentials() {
        ASCredentialIdentityStore.shared.getState { state in
            guard Self.isProviderEnabled(state) else { return }
            ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: [], completion: nil)
        }
    }

    static func fetchProviderEnabled(completion: @escaping (Bool) -> Void) {
        ASCredentialIdentityStore.shared.getState { state in
            completion(Self.isProviderEnabled(state))
        }
    }

    private static func isProviderEnabled(_ state: ASCredentialIdentityStoreState) -> Bool {
        if #available(iOS 17.0, *) {
            return state.isEnabled
        } else {
            return true
        }
    }
}
