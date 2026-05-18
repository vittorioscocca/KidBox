//
//  TravelTripPlaceImageLoader.swift
//  KidBox
//

import Foundation

actor TravelTripPlaceImageLoader {
    static let shared = TravelTripPlaceImageLoader()

    private var cache: [String: URL] = [:]

    func imageURL(for destination: String) async -> URL? {
        let key = destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        guard let url = await fetchWikipediaThumbnail(query: destination) else { return nil }
        cache[key] = url
        return url
    }

    private func fetchWikipediaThumbnail(query: String) async -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let title = await wikipediaTitle(for: trimmed, language: "it"),
           let url = await wikipediaSummaryThumbnail(title: title, language: "it") {
            return url
        }
        if let title = await wikipediaTitle(for: trimmed, language: "en"),
           let url = await wikipediaSummaryThumbnail(title: title, language: "en") {
            return url
        }
        return nil
    }

    private func wikipediaTitle(for query: String, language: String) async -> String? {
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count > 2,
                  let titles = json[1] as? [String],
                  let title = titles.first,
                  !title.isEmpty else { return nil }
            return title
        } catch {
            return nil
        }
    }

    private func wikipediaSummaryThumbnail(title: String, language: String) async -> URL? {
        let wikiTitle = title.replacingOccurrences(of: " ", with: "_")
        let encoded = wikiTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wikiTitle
        guard let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let thumb = json["thumbnail"] as? [String: Any],
               let source = thumb["source"] as? String,
               let imageURL = URL(string: source) {
                return imageURL
            }
            if let original = json["originalimage"] as? [String: Any],
               let source = original["source"] as? String,
               let imageURL = URL(string: source) {
                return imageURL
            }
            return nil
        } catch {
            return nil
        }
    }
}
