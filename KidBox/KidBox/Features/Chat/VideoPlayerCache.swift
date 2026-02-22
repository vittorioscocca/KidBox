//
//  VideoPlayerCache.swift
//  KidBox
//
//  Created by vscocca on 22/02/26.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VideoPlayerCache: ObservableObject {
    static let shared = VideoPlayerCache()
    
    private var players: [URL: AVPlayer] = [:]
    
    func player(for url: URL) -> AVPlayer {
        if let p = players[url] { return p }
        let p = AVPlayer(url: url)
        players[url] = p
        return p
    }
    
    func pause(url: URL) {
        players[url]?.pause()
    }
    
    // opzionale: limita memoria (LRU semplice)
    func trim(keeping urls: Set<URL>) {
        for (url, player) in players where !urls.contains(url) {
            player.pause()
            players[url] = nil
        }
    }
}
