//
//  DocumentLocalCacheTests.swift
//  KidBoxTests
//

import Testing
@testable import KidBox

struct DocumentLocalCacheTests {
    /// Il controllo gira sulla coda di NWPathMonitor: deve rispondere una volta sola, senza
    /// fermarsi sull'attore principale, anche quando lo si chiama più volte di seguito.
    @Test func hasNetworkRouteResponds() async {
        for _ in 0..<3 {
            _ = await DocumentLocalCache.hasNetworkRoute()
        }
    }
}
