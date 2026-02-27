//
//  AuthError.swift
//  KidBox
//
//  Created by vscocca on 27/02/26.
//


import Foundation

/// Errori "app-level" per flussi di autenticazione.
/// (Usali per normalizzare cancellazioni / token mancanti / casi generici)
enum AuthError: Error, Equatable {
    case cancelled
    case missingToken
    case unknown
    case invalidPresentation(String)
}

extension AuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Operazione annullata."
        case .missingToken:
            return "Token di accesso mancante."
        case .unknown:
            return "Errore sconosciuto."
        case .invalidPresentation(let message):
            return message
        }
    }
}
