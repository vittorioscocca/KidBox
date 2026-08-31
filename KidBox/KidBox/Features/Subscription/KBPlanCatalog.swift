//
//  KBPlanCatalog.swift
//  KidBox
//
//  Catalogo piani letto da Firestore (`config/plans`), con i valori compilati
//  come rete di sicurezza — stesso pattern di `config/nudges` / NudgeCatalog.
//
//  FONTE DI VERITÀ: `functions/plans.json`. Da lì il backend calcola le quote
//  che applica davvero e da lì viene pubblicato `config/plans`, che questa
//  classe legge per MOSTRARE quote, prezzi e feature. Il documento remoto è
//  materiale di presentazione: quanto storage e quanti messaggi AI la famiglia
//  ottenga davvero lo decide il backend, non ciò che il client ha letto qui.
//
//  L'ultimo catalogo valido viene tenuto in UserDefaults dell'app group, così
//  a freddo — prima ancora che Firestore risponda — le schermate non partono
//  dai valori compilati (potenzialmente vecchi) ma dall'ultimo listino visto.
//

import Foundation
import FirebaseFirestore

// MARK: - Modello

/// Voce dell'elenco feature di un piano. `text` può contenere i segnaposto
/// `{storage}` e `{aiLimit}`, risolti da `KBPlanSpec.renderedFeatures`.
struct KBPlanFeature: Codable, Hashable {
    let icon: String
    let text: String
    var strong: Bool = false

    private enum CodingKeys: String, CodingKey { case icon, text, strong }

    init(icon: String, text: String, strong: Bool = false) {
        self.icon = icon
        self.text = text
        self.strong = strong
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icon   = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        text   = try c.decode(String.self, forKey: .text)
        strong = try c.decodeIfPresent(Bool.self, forKey: .strong) ?? false
    }
}

/// Specifica di un piano così com'è pubblicata su `config/plans`.
struct KBPlanSpec: Codable {
    let id: String
    var order: Int = 0
    var displayName: String
    var storageBytes: Int64
    var aiLimit: Int
    var aiPeriod: String            // "daily" | "lifetime"
    var productId: String?
    var priceLabel: [String: String] = [:]
    var tagline: [String: String]    = [:]
    var badge: [String: String]      = [:]
    var features: [String: [KBPlanFeature]] = [:]

    /// Lingua da usare per i testi: quella del device se presente nel catalogo,
    /// altrimenti italiano (lingua sorgente del progetto).
    static var preferredLanguage: String {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "it"
        return String(code)
    }

    private func localized(_ map: [String: String]) -> String {
        map[Self.preferredLanguage] ?? map["it"] ?? map["en"] ?? ""
    }

    var localizedPriceLabel: String { localized(priceLabel) }
    var localizedTagline: String    { localized(tagline) }
    var localizedBadge: String      { localized(badge) }

    /// Quota storage in forma compatta da listino — "200 MB", "5 GB" — non il
    /// formato dettagliato di `formattedFileSize` ("5.00 GB"), che qui suonerebbe
    /// da schermata tecnica invece che da prezzo.
    var storageLabel: String {
        let lang = Self.preferredLanguage
        let mbUnit = lang == "fr" ? "Mo" : "MB"
        let gbUnit = lang == "fr" ? "Go" : "GB"
        let gb = Double(storageBytes) / 1_073_741_824
        if gb >= 1 {
            return gb == gb.rounded() ? "\(Int(gb)) \(gbUnit)" : String(format: "%.1f %@", gb, gbUnit)
        }
        let mb = Double(storageBytes) / 1_048_576
        return mb == mb.rounded() ? "\(Int(mb)) \(mbUnit)" : String(format: "%.1f %@", mb, mbUnit)
    }

    /// Feature nella lingua del device, con i segnaposto già risolti.
    var renderedFeatures: [KBPlanFeature] {
        let list = features[Self.preferredLanguage] ?? features["it"] ?? features["en"] ?? []
        let storage = storageLabel
        return list.map {
            KBPlanFeature(
                icon: $0.icon,
                text: $0.text
                    .replacingOccurrences(of: "{storage}", with: storage)
                    .replacingOccurrences(of: "{aiLimit}", with: "\(aiLimit)"),
                strong: $0.strong
            )
        }
    }
}

/// Payload del documento `config/plans`.
private struct KBPlansDocument: Codable {
    let version: Int
    let plans: [String: KBPlanSpec]
}

// MARK: - Catalogo

/// Accesso sincrono e thread-safe alle spec dei piani: `KBPlan` espone proprietà
/// non-async usate ovunque (anche fuori dal main actor), quindi il catalogo va
/// letto senza await e protetto da lock.
final class KBPlanCatalog: @unchecked Sendable {

    static let shared = KBPlanCatalog()

    private let lock = NSLock()
    private var specs: [String: KBPlanSpec]

    private let defaultsKey = "planCatalogJSON"
    private var store: UserDefaults? {
        UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
    }

    private init() {
        specs = Self.builtIn
        if let data = store?.data(forKey: defaultsKey),
           let cached = try? JSONDecoder().decode(KBPlansDocument.self, from: data) {
            specs = cached.plans
        }
        publishExtensionHints()
    }

    /// La Share Extension non ha Firebase e `KBStorageGateLite` è volutamente
    /// senza dipendenze: la quota Pro le arriva come stringa già pronta
    /// nell'app group, così anche lì il "passa a Pro per 5 GB" non è scritto a mano.
    private func publishExtensionHints() {
        store?.set(spec(for: .pro).storageLabel, forKey: "proStorageLabel")
    }

    /// Spec del piano, con fallback sul valore compilato: un catalogo remoto
    /// malformato non deve poter far sparire un piano dall'app.
    func spec(for plan: KBPlan) -> KBPlanSpec {
        lock.lock()
        defer { lock.unlock() }
        return specs[plan.rawValue] ?? Self.builtIn[plan.rawValue]!
    }

    /// Rilegge `config/plans`. Un errore (documento assente, permessi, campo
    /// malformato) lascia in piedi il catalogo precedente: non si degrada mai.
    func refresh() async {
        do {
            let snap = try await Firestore.firestore()
                .collection("config").document("plans").getDocument()
            guard let data = snap.data() else { return }

            // I timestamp di pubblicazione non sono serializzabili in JSON e non
            // servono al client: si scartano prima della decodifica.
            var payload = data
            payload.removeValue(forKey: "publishedAt")
            payload.removeValue(forKey: "publishedBy")

            let json = try JSONSerialization.data(withJSONObject: payload)
            let decoded = try JSONDecoder().decode(KBPlansDocument.self, from: json)
            guard decoded.plans["free"] != nil else { return }

            lock.lock()
            specs = decoded.plans
            lock.unlock()

            store?.set(json, forKey: defaultsKey)
            publishExtensionHints()
            KBLog.app.kbInfo("[Plans] catalogo remoto caricato, versione \(decoded.version)")
        } catch {
            KBLog.app.kbDebug("[Plans] catalogo remoto non disponibile, resto sull'ultimo valido: \(error.localizedDescription)")
        }
    }

    // MARK: - Rete di sicurezza compilata

    /// Valori minimi garantiti se il catalogo remoto non è mai arrivato.
    /// Volutamente scarni sulle feature: l'elenco lungo è materiale di listino
    /// e vive in `functions/plans.json`, non qui.
    private static let builtIn: [String: KBPlanSpec] = [
        "free": KBPlanSpec(
            id: "free", order: 0, displayName: "Free",
            storageBytes: 200 * 1024 * 1024, aiLimit: 5, aiPeriod: "lifetime",
            productId: nil,
            priceLabel: ["it": "Gratis", "en": "Free"],
            features: ["it": [KBPlanFeature(icon: "✓", text: "{storage} di storage famiglia", strong: true),
                              KBPlanFeature(icon: "💬", text: "{aiLimit} messaggi AI di prova, una tantum")],
                       "en": [KBPlanFeature(icon: "✓", text: "{storage} family storage", strong: true),
                              KBPlanFeature(icon: "💬", text: "{aiLimit} trial AI messages, one time only")]]
        ),
        "pro": KBPlanSpec(
            id: "pro", order: 1, displayName: "Pro",
            storageBytes: 5 * 1024 * 1024 * 1024, aiLimit: 30, aiPeriod: "daily",
            productId: "it.vittorioscocca.kidbox.pro.monthly",
            priceLabel: ["it": "€4,99/mese", "en": "€4.99/month"],
            badge: ["it": "Più popolare", "en": "Most popular"],
            features: ["it": [KBPlanFeature(icon: "☁️", text: "{storage} di storage famiglia", strong: true),
                              KBPlanFeature(icon: "💬", text: "{aiLimit} messaggi AI al giorno", strong: true)],
                       "en": [KBPlanFeature(icon: "☁️", text: "{storage} family storage", strong: true),
                              KBPlanFeature(icon: "💬", text: "{aiLimit} AI messages per day", strong: true)]]
        ),
        "max": KBPlanSpec(
            id: "max", order: 2, displayName: "Max",
            storageBytes: 20 * 1024 * 1024 * 1024, aiLimit: 100, aiPeriod: "daily",
            productId: "it.vittorioscocca.kidbox.max.monthly",
            priceLabel: ["it": "€9,99/mese", "en": "€9.99/month"],
            badge: ["it": "Migliore", "en": "Best value"],
            features: ["it": [KBPlanFeature(icon: "☁️", text: "{storage} di storage famiglia", strong: true),
                              KBPlanFeature(icon: "💬", text: "{aiLimit} messaggi AI al giorno", strong: true)],
                       "en": [KBPlanFeature(icon: "☁️", text: "{storage} family storage", strong: true),
                              KBPlanFeature(icon: "💬", text: "{aiLimit} AI messages per day", strong: true)]]
        ),
    ]
}
