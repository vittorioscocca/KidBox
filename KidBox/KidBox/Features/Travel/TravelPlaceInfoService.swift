//
//  TravelPlaceInfoService.swift
//  KidBox
//
//  Storia e paesaggio della destinazione, da Wikipedia.
//
//  Perché Wikipedia e non l'AI: il contenuto è fattuale e verificabile, ha già
//  testo e immagini, non costa nulla per chiamata e non consuma il budget AI
//  della famiglia. Un modello che "racconta" la storia di un paese piccolo è
//  esattamente il caso in cui inventa date e monumenti.
//

import Foundation

struct TravelPlaceInfo: Equatable {
    let title: String
    /// Riga breve sotto il titolo (es. "comune italiano").
    let subtitle: String
    /// Testo storico/descrittivo completo, diviso in paragrafi.
    let paragraphs: [String]
    let imageURLs: [URL]
    let wikipediaURL: URL?
    /// Dati Google del luogo: voto, indirizzo, foto, recensioni.
    var googleDetails: TravelPlaceDetails?

    /// Primo paragrafo, per le anteprime.
    var extract: String { paragraphs.first ?? "" }
}

enum TravelPlaceInfoError: Error {
    case notFound
    case network
}

actor TravelPlaceInfoService {
    static let shared = TravelPlaceInfoService()

    private var cache: [String: TravelPlaceInfo] = [:]

    func info(for place: String, familyId: String? = nil) async throws -> TravelPlaceInfo {
        let key = place.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { throw TravelPlaceInfoError.notFound }
        if let cached = cache[key], cached.googleDetails != nil || familyId == nil {
            return cached
        }

        // Italiano prima: per una località italiana l'articolo it.wikipedia è
        // quasi sempre più ricco di quello inglese.
        var base: TravelPlaceInfo?
        for language in ["it", "en"] where base == nil {
            base = await fetchInfo(place: place, language: language)
        }
        guard var info = base else { throw TravelPlaceInfoError.notFound }

        // Google è complementare, non alternativo: Wikipedia dà la storia,
        // Places dà voto, indirizzo, foto attuali e recensioni. Se fallisce, la
        // scheda resta valida con la sola parte enciclopedica.
        if let familyId, !familyId.isEmpty {
            info.googleDetails = try? await TravelPlacesService.fetchDetails(
                placeName: place,
                locationContext: place,
                familyId: familyId
            )
        }

        cache[key] = info
        return info
    }

    // MARK: - Wikipedia

    private func fetchInfo(place: String, language: String) async -> TravelPlaceInfo? {
        guard let title = await geoDisambiguatedTitle(for: place, language: language) else {
            return nil
        }
        guard let base = await summary(title: title, language: language) else { return nil }

        // Il riassunto è un paragrafo solo: per una scheda che deve raccontare
        // il posto serve il testo dell'articolo. Le due richieste in parallelo
        // perché indipendenti — in serie raddoppierebbero l'attesa.
        async let fullText = articleParagraphs(title: title, language: language)
        async let gallery = articleImages(title: title, language: language)

        let paragraphs = await fullText
        let extraImages = await gallery

        var images = base.imageURLs
        for url in extraImages where !images.contains(url) { images.append(url) }

        return TravelPlaceInfo(
            title: base.title,
            subtitle: base.subtitle,
            paragraphs: paragraphs.isEmpty ? base.paragraphs : paragraphs,
            imageURLs: Array(images.prefix(12)),
            wikipediaURL: base.wikipediaURL,
            googleDetails: nil
        )
    }

    /// Testo dell'articolo in paragrafi.
    ///
    /// `explaintext` restituisce prosa senza wiki-markup, quindi è mostrabile
    /// così com'è. Si scartano i paragrafi troppo corti: sono quasi sempre
    /// titoli di sezione rimasti isolati, non contenuto.
    private func articleParagraphs(title: String, language: String) async -> [String] {
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["query"] as? [String: Any],
                  let pages = query["pages"] as? [[String: Any]],
                  let text = pages.first?["extract"] as? String
            else { return [] }

            return text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 40 }
                // Un tetto c'è: certi comuni hanno articoli lunghissimi con
                // elenchi di frazioni e gemellaggi che qui non servono.
                .prefix(14)
                .map { $0 }
        } catch {
            return []
        }
    }

    /// Immagini dell'articolo, per la galleria.
    private func articleImages(title: String, language: String) async -> [URL] {
        let wikiTitle = title.replacingOccurrences(of: " ", with: "_")
        let encoded = wikiTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wikiTitle
        guard let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/media-list/\(encoded)") else {
            return []
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]]
            else { return [] }

            var urls: [URL] = []
            for item in items {
                // Solo immagini: la media-list contiene anche audio e video.
                guard (item["type"] as? String) == "image" else { continue }
                guard let srcset = item["srcset"] as? [[String: Any]] else { continue }
                // L'ultima entry è la risoluzione più alta.
                guard let src = srcset.last?["src"] as? String else { continue }
                let normalized = src.hasPrefix("//") ? "https:" + src : src
                if let imageURL = URL(string: normalized), !urls.contains(imageURL) {
                    urls.append(imageURL)
                }
            }
            return urls
        } catch {
            return []
        }
    }

    /// Titolo dell'articolo che descrive un LUOGO.
    ///
    /// Il criterio di disambiguazione è la presenza di coordinate geografiche:
    /// l'articolo di un comune le ha, quello di una persona no. Serve perché
    /// diverse località italiane sono omonime di persone — cercando
    /// "Margherita di Savoia" Wikipedia restituisce la regina, non il paese in
    /// provincia di Barletta, e la scheda mostrerebbe una biografia.
    private func geoDisambiguatedTitle(for place: String, language: String) async -> String? {
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: place),
            URLQueryItem(name: "gsrlimit", value: "5"),
            // `coordinates` è il discriminante luogo/persona.
            URLQueryItem(name: "prop", value: "coordinates|pageprops"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["query"] as? [String: Any],
                  let pages = query["pages"] as? [[String: Any]]
            else { return nil }

            // I risultati arrivano senza ordine garantito: `index` conserva il
            // ranking di rilevanza della ricerca.
            let ranked = pages.sorted {
                ($0["index"] as? Int ?? .max) < ($1["index"] as? Int ?? .max)
            }
            for page in ranked {
                let isDisambiguation = (page["pageprops"] as? [String: Any])?["disambiguation"] != nil
                guard !isDisambiguation else { continue }
                guard page["coordinates"] != nil else { continue }
                if let title = page["title"] as? String, !title.isEmpty { return title }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func summary(title: String, language: String) async -> TravelPlaceInfo? {
        let wikiTitle = title.replacingOccurrences(of: " ", with: "_")
        let encoded = wikiTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wikiTitle
        guard let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            let extract = (json["extract"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !extract.isEmpty else { return nil }

            var images: [URL] = []
            if let original = json["originalimage"] as? [String: Any],
               let source = original["source"] as? String,
               let imageURL = URL(string: source) {
                images.append(imageURL)
            }
            if let thumb = json["thumbnail"] as? [String: Any],
               let source = thumb["source"] as? String,
               let imageURL = URL(string: source),
               !images.contains(imageURL) {
                images.append(imageURL)
            }

            let pageURL = ((json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String

            return TravelPlaceInfo(
                title: json["title"] as? String ?? title,
                subtitle: json["description"] as? String ?? "",
                paragraphs: [extract],
                imageURLs: images,
                wikipediaURL: pageURL.flatMap { URL(string: $0) },
                googleDetails: nil
            )
        } catch {
            return nil
        }
    }
}
