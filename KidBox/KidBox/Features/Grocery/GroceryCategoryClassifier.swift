//
//  GroceryCategoryClassifier.swift
//  KidBox
//
//  Assegna da sola la categoria a un prodotto della lista della spesa.
//
//  1. Apple Intelligence (Foundation Models, sul telefono): sceglie fra le
//     categorie fisse di `KBGroceryCategory.suggested`. Capisce il prodotto in
//     italiano, inglese, francese e spagnolo e risponde sempre con la chiave
//     italiana, che è quella che si salva (vedi `KBGroceryCategory`).
//  2. Senza Apple Intelligence: piccolo dizionario di parole chiave nelle
//     stesse quattro lingue.
//  3. Se nessuno dei due ha un'idea: `nil`, e la lista lo mostra in «Altro».
//

import Foundation
import SwiftData
import FoundationModels

enum GroceryCategoryClassifier {

    /// Categoria da salvare in `KBGroceryItem.category`, oppure `nil` se non si capisce.
    static func category(for productName: String) async -> String? {
        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let pick = try await session.respond(
                    to: "Product: \(name)",
                    generating: GroceryAisle.self,
                    options: GenerationOptions(temperature: 0)
                ).content
                if let key = pick.categoryKey {
                    KBLog.ai.kbInfo("Grocery category on-device: \(key)")
                    return key
                }
                // «other» dal modello: vale la pena dare una chance al dizionario.
            } catch {
                KBLog.ai.kbInfo("Grocery category on-device fallita: \(error.localizedDescription)")
            }
        }
        return keywordCategory(for: name)
    }

    /// Dà una categoria alle voci appena create che non ne hanno, senza far
    /// aspettare chi le ha create. Tocca solo le voci ancora senza categoria
    /// quando il modello risponde, e manda un solo flush alla fine.
    @MainActor
    static func assignMissing(
        to items: [(id: String, name: String)],
        familyId: String,
        modelContext: ModelContext
    ) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            var changed = false
            for entry in items {
                guard let found = await category(for: entry.name) else { continue }
                let itemId = entry.id
                let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == itemId })
                guard let item = try? modelContext.fetch(desc).first,
                      !item.isDeleted,
                      (item.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                item.category = found
                item.updatedAt = Date()
                item.syncState = .pendingUpsert
                item.lastSyncError = nil
                try? modelContext.save()
                SyncCenter.shared.enqueueGroceryUpsert(itemId: itemId, familyId: familyId, modelContext: modelContext)
                changed = true
            }
            if changed { await SyncCenter.shared.flushGrocery(modelContext: modelContext) }
        }
    }

    private static let instructions = """
    You put one grocery product into the supermarket aisle where it is found. \
    The product name can be in Italian, English, French or Spanish. \
    Answer with the aisle only. If the product does not clearly belong to any aisle, answer other.
    """

    // MARK: - Ripiego a parole chiave

    /// Parole intere o radici: si confronta con `contains` sul nome in minuscolo
    /// e senza accenti. L'ordine conta: «latte di cocco» o «gelato» vanno
    /// guardati prima di «latte».
    private static let keywords: [(category: String, words: [String])] = [
        ("Surgelati", ["surgelat", "gelato", "ghiacciol", "frozen", "ice cream", "congel", "surgele", "helado", "bastoncini di pesce", "findus"]),
        ("Cura Personale", ["shampoo", "balsamo", "dentifric", "spazzolin", "bagnoschiuma", "sapone", "deodorante", "assorbent", "cotton fioc", "rasoi", "crema viso", "crema corpo", "toothpaste", "toothbrush", "conditioner", "razor", "deodorant", "soap", "dentifrice", "brosse a dents", "gel douche", "pasta de dientes", "cepillo de dientes", "jabon", "champu"]),
        ("Pulizia", ["detersivo", "detergent", "ammorbidente", "candeggina", "sgrassat", "spugn", "carta igienica", "scottex", "carta da cucina", "sacchi", "lavastoviglie", "pastiglie", "anticalcare", "bleach", "dish soap", "laundry", "toilet paper", "paper towel", "trash bag", "lessive", "javel", "papier toilette", "sopalin", "lejia", "suavizante", "papel higienico", "bolsas de basura"]),
        ("Frutta e Verdura", [" mela ", " mele ", " pera ", " pere ", "banan", "arance", "arancia", "limon", "fragol", " uva ", " pesca ", "pesche", "kiwi", "anguria", "melone", "ananas", "insalata", "lattuga", "rucola", "pomodor", "zucchin", "carot", "patat", "cipoll", "aglio", "spinaci", "broccoli", "cavol", "peperon", "melanzan", "finocch", "sedano", "funghi", "frutta", "verdura", "basilico", "prezzemolo", "apple", "orange", "lemon", "strawberr", "grape", "tomato", "potato", "onion", "garlic", "carrot", "lettuce", "spinach", "cucumber", "cetriol", "fruit", "vegetable", "pomme", "poire", "banane", "citron", "fraise", "raisin", "tomate", "pomme de terre", "oignon", " ail ", "carotte", "salade", "legume", "manzana", "naranja", "limon", "fresa", "uvas", "cebolla", "ajo", "zanahoria", "lechuga", "verdura", "fruta"]),
        ("Carne e Pesce", ["carne", "pollo", "tacchino", "manzo", "maiale", "vitello", "salsiccia", "prosciutto", "salame", "bresaola", "mortadella", "speck", "affettat", "hamburger", "bistecc", "macinato", "pesce", "salmone", "tonno", "merluzzo", "orata", "branzino", "gamber", "calamar", "cozze", "vongol", "chicken", "turkey", "beef", "pork", " ham ", "sausage", "fish", "salmon", "tuna", "shrimp", "poulet", "dinde", "boeuf", "porc", "jambon", "saucisse", "poisson", "saumon", "thon", "crevette", "pollo", "pavo", "ternera", "cerdo", "jamon", "salchicha", "pescado", "atun", "gambas"]),
        ("Latticini", ["latte", "yogurt", "burro", "formaggio", "mozzarella", "parmigiano", "grana", "ricotta", "mascarpone", "panna", "stracchino", "provola", "pecorino", "scamorza", "uova", "uovo", "milk", "butter", "cheese", "cream", " egg", "yoghurt", "lait", "beurre", "fromage", "creme fraiche", "oeuf", "leche", "mantequilla", "queso", "nata", "huevo"]),
        ("Pane e Cereali", ["pane", "pasta", "riso", "farina", "cereali", "fette biscottate", "grissini", "cracker", "piadina", "pizza", "spaghetti", "penne", "fusilli", "couscous", "avena", "polenta", "lievito", "bread", " rice ", "flour", "cereal", " oat", "noodle", "pain", "riz", "farine", "cereale", "avoine", "pates", " pan ", "arroz", "harina", "cereales", "avena", "fideos"]),
        ("Bevande", ["acqua", "succo", "birra", " vino ", "coca", "aranciata", " te ", "caffe", "camomilla", "tisana", "bibita", "spremuta", "sciroppo", "prosecco", "spumante", "liquore", "water", "juice", "beer", "wine", "coffee", " tea ", " soda ", " eau ", " jus ", "biere", " vin ", "cafe", " the ", "agua", "zumo", "cerveza", "refresco"]),
        ("Dolci e Snack", ["biscott", "cioccolat", "nutella", "merendin", "caramell", "gomme", "patatine", "snack", "crostat", "torta", "cornett", "brioche", "marmellata", "miele", "wafer", "gelatina", "budino", "noccioline", "popcorn", "cookie", "chocolate", "candy", "chips", " cake", " jam ", "honey", "biscuit", "chocolat", "bonbon", "gateau", "confiture", "miel", "galleta", "chocolate", "caramelo", "pastel", "mermelada"]),
    ]

    static func keywordCategory(for name: String) -> String? {
        let haystack = " " + normalize(name) + " "
        for entry in keywords {
            for word in entry.words where haystack.contains(normalize(word)) {
                return entry.category
            }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .lowercased()
    }
}

// MARK: - Scelta del modello

/// Reparti del supermercato. I nomi inglesi sono per il modello; la chiave
/// salvata è quella italiana di `KBGroceryCategory.suggested`.
@Generable
enum GroceryAisle: String {
    case fruitAndVegetables, meatAndFish, dairyAndEggs, breadPastaAndCereals, frozen
    case drinks, sweetsAndSnacks, householdCleaning, personalCare, other

    var categoryKey: String? {
        switch self {
        case .fruitAndVegetables:   return "Frutta e Verdura"
        case .meatAndFish:          return "Carne e Pesce"
        case .dairyAndEggs:         return "Latticini"
        case .breadPastaAndCereals: return "Pane e Cereali"
        case .frozen:               return "Surgelati"
        case .drinks:               return "Bevande"
        case .sweetsAndSnacks:      return "Dolci e Snack"
        case .householdCleaning:    return "Pulizia"
        case .personalCare:         return "Cura Personale"
        case .other:                return nil
        }
    }
}
