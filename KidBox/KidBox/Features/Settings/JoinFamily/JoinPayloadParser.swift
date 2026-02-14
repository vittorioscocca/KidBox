//
//  JoinPayloadParser.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import OSLog

enum JoinPayloadParser {
    
    /// Extracts the membership invite code from a raw QR payload.
    ///
    /// Supported formats:
    /// 1️⃣ Deep link: `kidbox://join?...&code=XXXX`
    /// 2️⃣ Plain string: `XXXX`
    ///
    /// - Important: Never log the actual invite code (security-sensitive).
    /// - Returns: Normalized code if found, otherwise `nil`.
    static func extractCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        KBLog.sync.debug("JoinPayloadParser extractCode start payloadLen=\(trimmed.count, privacy: .public)")
        
        // Case 1️⃣: kidbox://join?...&code=XXXX
        if let comps = URLComponents(string: trimmed),
           let items = comps.queryItems,
           let code = items.first(where: { $0.name.lowercased() == "code" })?.value,
           !code.isEmpty {
            
            KBLog.sync.info("JoinPayloadParser code extracted from URL payload")
            return code
        }
        
        // Case 2️⃣: plain string
        if trimmed.count >= 4,
           trimmed.count <= 32,
           trimmed.range(of: "://") == nil,
           trimmed.contains("?") == false {
            
            KBLog.sync.info("JoinPayloadParser code extracted from plain payload")
            return trimmed
        }
        
        KBLog.sync.debug("JoinPayloadParser no valid code found")
        return nil
    }
}
