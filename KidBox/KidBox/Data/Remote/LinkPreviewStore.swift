//
//  LinkPreviewStore.swift
//  KidBox
//
//  Created by vscocca on 28/02/26.
//

import Foundation
import SwiftUI
import Combine

// MARK: - LinkPreviewStore
//
// ObservableObject SEPARATO dal ChatViewModel.
// Aggiornarlo non invalida la LazyVStack dei messaggi perché
// BubbleRowView non osserva questo store — lo legge solo LinkPreviewView
// tramite @EnvironmentObject, che è scoped alla singola bubble.

@MainActor
final class LinkPreviewStore: ObservableObject {
    static let shared = LinkPreviewStore()
    private init() {}
    
    // Dizionario url → stato. Viene letto solo da LinkPreviewView.
    @Published private(set) var previews: [URL: LinkPreviewState] = [:]
    
    enum LinkPreviewState {
        case loading
        case ready(LinkPreviewMetadata)
        case failed
    }
    
    /// Idempotente: se l'URL è già in cache (o in corso) non fa nulla.
    func fetchIfNeeded(for url: URL) {
        guard previews[url] == nil else { return }
        previews[url] = .loading
        Task {
            let meta = await LinkMetadataService.shared.fetch(url: url)
            previews[url] = meta.map { .ready($0) } ?? .failed
        }
    }
}

// MARK: - LinkPreviewMetadata

struct LinkPreviewMetadata {
    let title: String?
    let description: String?
    let imageURL: URL?
}

// MARK: - LinkMetadataService (background actor)
// Tutto il lavoro pesante su un actor separato: zero pressione sul Main thread.

actor LinkMetadataService {
    static let shared = LinkMetadataService()
    private init() {}
    private let prefix = "linkMeta_"
    
    func fetch(url: URL) async -> LinkPreviewMetadata? {
        if let cached = readCache(url: url) { return cached }
        guard let meta = await fetchRemote(url: url) else { return nil }
        writeCache(meta, url: url)
        return meta
    }
    
    private func readCache(url: URL) -> LinkPreviewMetadata? {
        guard let dict = UserDefaults.standard.dictionary(forKey: prefix + url.absoluteString)
        else { return nil }
        return LinkPreviewMetadata(
            title: dict["title"] as? String,
            description: dict["description"] as? String,
            imageURL: (dict["imageURL"] as? String).flatMap { URL(string: $0) }
        )
    }
    
    private func writeCache(_ m: LinkPreviewMetadata, url: URL) {
        var dict: [String: String] = [:]
        if let t = m.title { dict["title"] = t }
        if let d = m.description { dict["description"] = d }
        if let i = m.imageURL { dict["imageURL"] = i.absoluteString }
        UserDefaults.standard.set(dict, forKey: prefix + url.absoluteString)
    }
    
    private func fetchRemote(url: URL) async -> LinkPreviewMetadata? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        
        return parseOG(html: html, baseURL: url)
    }
    
    private func parseOG(html: String, baseURL: URL) -> LinkPreviewMetadata? {
        func og(_ k: String) -> String? {
            let patterns = [
                "property=[\"']og:\(k)[\"'][^>]+content=[\"']([^\"']+)[\"']",
                "content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:\(k)[\"']",
            ]
            for pat in patterns {
                if let r = try? NSRegularExpression(
                    pattern: pat,
                    options: [.caseInsensitive, .dotMatchesLineSeparators]),
                   let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let rng = Range(m.range(at: 1), in: html) {
                    return String(html[rng]).htmlEntityDecoded
                }
            }
            return nil
        }
        
        let title: String? = og("title") ?? {
            if let r = try? NSRegularExpression(
                pattern: "<title[^>]*>\\s*([^<]+?)\\s*</title>",
                options: .caseInsensitive),
               let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let rng = Range(m.range(at: 1), in: html) {
                return String(html[rng]).htmlEntityDecoded
            }
            return nil
        }()
        
        let img: URL? = og("image").flatMap { raw -> URL? in
            if raw.hasPrefix("http") { return URL(string: raw) }
            if raw.hasPrefix("//")   { return URL(string: "https:" + raw) }
            if raw.hasPrefix("/")    {
                return URL(string: (baseURL.scheme ?? "https") + "://" + (baseURL.host ?? "") + raw)
            }
            return nil
        }
        
        guard title != nil || img != nil else { return nil }
        return LinkPreviewMetadata(title: title, description: og("description"), imageURL: img)
    }
}

private extension String {
    nonisolated var htmlEntityDecoded: String {
        [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),
         ("&#39;","'"),("&apos;","'"),("&nbsp;"," ")]
            .reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
