//
//  JoinPayloadParser.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation

enum JoinPayloadParser {
    static func extractCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Caso: kidbox://join?...&code=XXXX
        if let comps = URLComponents(string: trimmed),
           let items = comps.queryItems,
           let code = items.first(where: { $0.name.lowercased() == "code" })?.value,
           !code.isEmpty {
            return code
        }
        
        // Caso: stringa pura
        if trimmed.count >= 4, trimmed.count <= 32,
           trimmed.range(of: "://") == nil,
           trimmed.contains("?") == false {
            return trimmed
        }
        
        return nil
    }
}
