//
//  AppLanguage.swift
//  KidBox
//
//  Lingua dell'app selezionabile in-app. Applicata a caldo (senza riavvio):
//  vedi `LanguageManager` per i dettagli del meccanismo.
//

import Foundation
import Combine
import ObjectiveC

/// Lingue selezionabili dall'utente nei Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case italian = "it"
    case english = "en"
    case french  = "fr"
    case spanish = "es"

    var id: String { rawValue }

    /// Etichetta mostrata: ogni lingua nel proprio idioma (endonimo).
    var label: String {
        switch self {
        case .system:  return NSLocalizedString("Lingua del sistema", comment: "System language option")
        case .italian: return "Italiano"
        case .english: return "English"
        case .french:  return "Français"
        case .spanish: return "Español"
        }
    }

    /// Emoji bandiera; `system` usa un SF Symbol (vedi view).
    var flag: String? {
        switch self {
        case .system:  return nil
        case .italian: return "🇮🇹"
        case .english: return "🇬🇧"
        case .french:  return "🇫🇷"
        case .spanish: return "🇪🇸"
        }
    }

    /// `Locale` esplicita per questa lingua, `nil` per `.system` (segue il dispositivo).
    var explicitLocale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }
}

/// Gestisce persistenza e applicazione a caldo della lingua scelta.
///
/// Due meccanismi lavorano insieme, entrambi live (nessun riavvio richiesto):
/// 1. `current` è `@Published` → la root dell'app osserva questo oggetto e
///    ricalcola `.environment(\.locale, ...)`, che aggiorna istantaneamente
///    tutti i `Text(...)` basati su `LocalizedStringKey`.
/// 2. `Bundle.kb_setLanguage(...)` sostituisce a runtime il bundle da cui
///    `NSLocalizedString`/`Bundle.main.localizedString` leggono le stringhe —
///    necessario per le tante proprietà `String` (non `Text` diretto) create
///    con `NSLocalizedString(...)` in giro per l'app (stati, filtri, ecc.),
///    che l'`.environment(\.locale)` da solo non aggiornerebbe.
///
/// Eccezione nota: i dialoghi di permesso di sistema (fotocamera, Salute...)
/// sono localizzati da iOS stesso e restano nella lingua precedente finché
/// l'app non viene davvero riavviata — non è possibile intervenire su questi.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let appleLanguagesKey = "AppleLanguages"
    private static let selectionKey = "kb_selectedLanguage"

    @Published private(set) var current: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.selectionKey)
        current = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        Bundle.kb_setLanguage(Self.resolvedLanguageCode(for: current))
    }

    /// Applica la scelta immediatamente: aggiorna la UI corrente senza riavvio.
    func apply(_ lang: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(lang.rawValue, forKey: Self.selectionKey)
        switch lang {
        case .system:
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        default:
            defaults.set([lang.rawValue], forKey: Self.appleLanguagesKey)
        }
        Bundle.kb_setLanguage(Self.resolvedLanguageCode(for: lang))
        current = lang
    }

    /// Per `.system`: replica la stessa euristica di `kbDeviceLocale()` per
    /// scegliere quale `.lproj` usare tra quelli supportati dall'app.
    private static func resolvedLanguageCode(for lang: AppLanguage) -> String {
        guard lang == .system else { return lang.rawValue }
        let supported = AppLanguage.allCases.compactMap { $0 == .system ? nil : $0.rawValue }
        let auto = Locale.autoupdatingCurrent
        if auto.language.languageCode?.identifier == "en", auto.region?.identifier == "IT" {
            return "it"
        }
        if let code = auto.language.languageCode?.identifier, supported.contains(code) {
            return code
        }
        if let preferred = Locale.preferredLanguages.first {
            let code = Locale(identifier: preferred).language.languageCode?.identifier
            if let code, supported.contains(code) { return code }
        }
        return "it"
    }
}

// MARK: - Bundle live-swap

private var kbLocalizedBundleKey: UInt8 = 0

/// Sottoclasse che intercetta `localizedString(forKey:value:table:)` per
/// leggere da un `.lproj` scelto a runtime invece di quello risolto al lancio.
private final class KBLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let bundle = objc_getAssociatedObject(self, &kbLocalizedBundleKey) as? Bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Sostituisce a runtime la classe di `Bundle.main` (una volta sola) e
    /// aggiorna il bundle associato al codice lingua richiesto. Da qui in poi
    /// `NSLocalizedString`/`Bundle.main.localizedString` leggono dal nuovo `.lproj`.
    fileprivate static func kb_setLanguage(_ languageCode: String) {
        if object_getClass(Bundle.main) != KBLocalizedBundle.self {
            object_setClass(Bundle.main, KBLocalizedBundle.self)
        }
        let target = Bundle.main.path(forResource: languageCode, ofType: "lproj").flatMap(Bundle.init(path:))
        objc_setAssociatedObject(Bundle.main, &kbLocalizedBundleKey, target, .OBJC_ASSOCIATION_RETAIN)
    }
}
