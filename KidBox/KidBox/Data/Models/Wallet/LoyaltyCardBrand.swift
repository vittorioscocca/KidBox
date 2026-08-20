//
//  LoyaltyCardBrand.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Catalogo interno curato di negozi/brand per le carte fedeltà.
//  Non esiste un'API pubblica affidabile con loghi/colori dei negozi
//  (CardPlus/Stocard usano database proprietari): costruiamo un JSON
//  bundle con nome + colori brand (fatti pubblici) + il `domain` ufficiale
//  del brand e il `logoURL` da cui il logo viene scaricato A RUNTIME
//  (servizi favicon pubblici: Google s2/favicons, DuckDuckGo ip3).
//  Nessun asset immagine è incluso nel bundle: il logo è caricato via
//  `AsyncImage` e messo in cache da `URLCache.shared`; quando manca o non
//  carica si ricade sul wordmark testuale (nome del brand), che resta il
//  fallback grafico di sempre.
//

import Foundation

/// Singolo brand del catalogo carte fedeltà.
struct LoyaltyCardBrand: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Nomi alternativi usati per la ricerca (es. "Iper" per "Iper, La grande i").
    let aliases: [String]
    let primaryColorHex: String
    let secondaryColorHex: String
    /// Raw value plausibile per il formato barcode più comune di questo brand
    /// (es. "ean13", "code128", "qr").
    let defaultBarcodeFormat: String
    /// Marcati come "popolari" per la sezione in alto del picker.
    let isPopular: Bool
    /// Dominio ufficiale del brand (es. "conad.it"), sorgente del logo.
    /// Opzionale: alcuni brand generici (farmacie comunali) non ne hanno uno.
    let domain: String?
    /// URL completo da cui scaricare il logo a runtime. `nil` per i brand
    /// senza logo verificato → la UI ricade sul wordmark testuale.
    let logoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, primaryColorHex, secondaryColorHex, defaultBarcodeFormat, isPopular, domain, logoURL
    }

    init(id: String, name: String, aliases: [String] = [], primaryColorHex: String, secondaryColorHex: String, defaultBarcodeFormat: String = "code128", isPopular: Bool = false, domain: String? = nil, logoURL: String? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.defaultBarcodeFormat = defaultBarcodeFormat
        self.isPopular = isPopular
        self.domain = domain
        self.logoURL = logoURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        primaryColorHex = try c.decode(String.self, forKey: .primaryColorHex)
        secondaryColorHex = try c.decodeIfPresent(String.self, forKey: .secondaryColorHex) ?? primaryColorHex
        defaultBarcodeFormat = try c.decodeIfPresent(String.self, forKey: .defaultBarcodeFormat) ?? "code128"
        isPopular = try c.decodeIfPresent(Bool.self, forKey: .isPopular) ?? false
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        logoURL = try c.decodeIfPresent(String.self, forKey: .logoURL)
    }

    /// Prima lettera del nome, normalizzata (maiuscola, senza accenti) — usata
    /// per raggruppare l'indice alfabetico A-Z nel picker.
    var indexLetter: String {
        guard let first = name.folding(options: .diacriticInsensitive, locale: .current).first else { return "#" }
        let upper = String(first).uppercased()
        return upper.first?.isLetter == true ? upper : "#"
    }
}

/// Loader del catalogo `LoyaltyCardCatalog.json` dal bundle, con ricerca
/// per nome/alias e raggruppamento alfabetico.
enum LoyaltyCardCatalog {

    /// Catalogo caricato una sola volta (immutabile, ordinato per nome).
    static let all: [LoyaltyCardBrand] = load()

    private static func load() -> [LoyaltyCardBrand] {
        guard let url = Bundle.main.url(forResource: "LoyaltyCardCatalog", withExtension: "json") else {
            KBLog.data.kbError("LoyaltyCardCatalog: file not found in bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let brands = try JSONDecoder().decode([LoyaltyCardBrand].self, from: data)
            return brands.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            KBLog.data.kbError("LoyaltyCardCatalog: decode failed err=\(error.localizedDescription)")
            return []
        }
    }

    static func brand(id: String) -> LoyaltyCardBrand? {
        all.first { $0.id == id }
    }

    /// Brand marcati come "popolari" (sezione in alto del picker).
    static var popular: [LoyaltyCardBrand] {
        all.filter { $0.isPopular }
    }

    /// Ricerca case/diacritic-insensitive su nome + alias.
    static func search(_ query: String) -> [LoyaltyCardBrand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { brand in
            if brand.name.localizedStandardContains(q) { return true }
            return brand.aliases.contains { $0.localizedStandardContains(q) }
        }
    }

    /// Raggruppamento alfabetico per l'indice laterale A-Z del picker.
    static func groupedByIndexLetter(_ brands: [LoyaltyCardBrand]) -> [(letter: String, brands: [LoyaltyCardBrand])] {
        let grouped = Dictionary(grouping: brands, by: { $0.indexLetter })
        return grouped.keys.sorted().map { letter in
            (letter: letter, brands: (grouped[letter] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }
}
