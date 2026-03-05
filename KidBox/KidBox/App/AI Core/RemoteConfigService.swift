//
//  RemoteConfigService.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//

import Foundation
import FirebaseRemoteConfig
import OSLog

/// Fetches and caches runtime configuration from Firebase Remote Config.
///
/// Usage:
/// ```swift
/// let key = try await RemoteConfigService.shared.anthropicAPIKey()
/// ```
final class RemoteConfigService {
    
    static let shared = RemoteConfigService()
    
    private let log = Logger(subsystem: "com.kidbox", category: "remote_config")
    private let config = RemoteConfig.remoteConfig()
    
    private init() {
        let settings = RemoteConfigSettings()
        // In produzione fetch ogni ora. In debug ogni 0 secondi.
#if DEBUG
        settings.minimumFetchInterval = 0
#else
        settings.minimumFetchInterval = 3600
#endif
        config.configSettings = settings
    }
    
    /// Returns the Anthropic API key from Remote Config.
    /// Fetches fresh values if needed, falls back to cached.
    func anthropicAPIKey() async throws -> String {
        do {
            let status = try await config.fetchAndActivate()
            log.debug("RemoteConfig fetch status: \(String(describing: status))")
        } catch {
            log.warning("RemoteConfig fetch failed, using cached: \(error.localizedDescription)")
            // Non blocchiamo — usiamo il valore cached se disponibile
        }
        
        let key = config.configValue(forKey: "anthropic_api_key").stringValue
        guard !key.isEmpty else {
            log.error("RemoteConfig: anthropic_api_key is empty")
            throw RemoteConfigError.missingKey("anthropic_api_key non configurata.")
        }
        
        return key
    }
}

enum RemoteConfigError: LocalizedError {
    case missingKey(String)
    
    var errorDescription: String? {
        switch self {
        case .missingKey(let msg): return msg
        }
    }
}
