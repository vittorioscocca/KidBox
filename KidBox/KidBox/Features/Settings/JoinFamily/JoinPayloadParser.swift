//
//  JoinPayloadParser.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation

enum JoinPayloadParser {
    static func extractCode(from raw: String) -> String? {
        // Caso 1: è già un codice (senza spazi)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 4, trimmed.count <= 32, trimmed.range(of: "://") == nil, trimmed.contains("?") == false {
            return trimmed
        }
        
        // Caso 2: kidbox://join?code=XXXX
        if let url = URLComponents(string: trimmed),
           let items = url.queryItems,
           let code = items.first(where: { $0.name.lowercased() == "code" })?.value,
           !code.isEmpty {
            return code
        }
        
        return nil
    }
}
