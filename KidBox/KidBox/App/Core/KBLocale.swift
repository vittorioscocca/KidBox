import Foundation

func kbDeviceLocale() -> Locale {
    // Se l'utente ha scelto esplicitamente una lingua nei Settings dell'app,
    // usala per date/calendari (nomi dei giorni, mesi, ecc.), indipendentemente
    // dalla regione del dispositivo.
    let selected = LanguageManager.shared.current
    if let explicit = selected.explicitLocale {
        return explicit
    }
    let auto = Locale.autoupdatingCurrent
    if auto.language.languageCode?.identifier == "en",
       auto.region?.identifier == "IT" {
        return Locale(identifier: "it_IT")
    }
    if auto.language.languageCode != nil {
        return auto
    }
    if let language = Locale.preferredLanguages.first, !language.isEmpty {
        return Locale(identifier: language)
    }
    return auto
}

func kbDeviceCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = kbDeviceLocale()
    calendar.firstWeekday = Calendar.autoupdatingCurrent.firstWeekday
    return calendar
}
