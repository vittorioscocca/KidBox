//
//  KBDemoSeed+Sections.swift
//  KidBox
//
//  Solo build di sviluppo. Completa la famiglia inventata di `KBDemoSeed` con
//  le sezioni che servono agli screenshot della landing e degli store: salute
//  di Marco, documenti, chat, un viaggio con l'itinerario, password, notizie e
//  posizioni. Quello che in app arriva dal server (notizie, posizioni degli
//  altri, piano) qui è finto e resta in memoria: niente esce dal telefono.
//
//  Contenuti in italiano e in inglese (`-KBDemoLang it|en`); spagnolo e
//  francese usano l'inglese.
//

#if DEBUG
import CryptoKit
import Foundation
import SwiftData

extension KBDemoSeed {

    static var isActive: Bool { CommandLine.arguments.contains("-KBDemoSeed") }

    static var demoLang: String {
        let args = CommandLine.arguments
        let lang = args.firstIndex(of: "-KBDemoLang").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "it"
        return lang == "it" ? "it" : "en"
    }

    static let grandmaUid = "demo-nonna"

    // MARK: - Dati locali

    @MainActor
    static func seedSections(_ ctx: ModelContext, day: (Int, Int, Int) -> Date) {
        let it = demoLang == "it"
        let fid = familyId
        let me = meUid
        let partner = "demo-luca"
        let child = "demo-marco"

        ctx.insert(KBFamilyMember(id: "m-\(grandmaUid)", familyId: fid, userId: grandmaUid, role: "member",
                                  displayName: it ? "Nonna Giulia" : "Grandma Giulia", updatedBy: me))

        // Salute di Marco
        ctx.insert(KBMedicalVisit(familyId: fid, childId: child, date: day(-20, 10, 0), doctorName: "Dr. Bianchi",
                                  doctorSpecialization: .pediatra,
                                  reason: it ? "Bilancio di salute degli 8 anni" : "8-year check-up",
                                  diagnosis: it ? "Crescita regolare, peso e altezza nella norma" : "Healthy growth, weight and height on track",
                                  recommendations: it ? "Vitamina D fino a marzo, controllo vista a scuola" : "Vitamin D until March, eye test at school",
                                  visitStatus: .completed, createdBy: me))
        ctx.insert(KBMedicalVisit(familyId: fid, childId: child, date: day(-45, 16, 30), doctorName: "Dr.ssa Ferri",
                                  doctorSpecialization: .otorinolaringoiatra,
                                  reason: it ? "Mal d'orecchio" : "Earache",
                                  diagnosis: it ? "Otite media, risolta in una settimana" : "Middle-ear infection, cleared in a week",
                                  visitStatus: .completed, createdBy: partner))
        ctx.insert(KBMedicalVisit(familyId: fid, childId: child, date: day(2, 9, 15), doctorName: "Dr. Bianchi",
                                  doctorSpecialization: .pediatra,
                                  reason: it ? "Controllo dopo l'otite" : "Follow-up after the ear infection",
                                  visitStatus: .booked, reminderOn: true, createdBy: me))
        ctx.insert(KBVaccine(familyId: fid, childId: child, vaccineType: .esavalente, status: .administered,
                             doseNumber: 3, totalDoses: 3, administeredDate: day(-365 * 7, 10, 0), createdBy: me))
        ctx.insert(KBVaccine(familyId: fid, childId: child, vaccineType: .mpr, status: .administered,
                             doseNumber: 2, totalDoses: 2, administeredDate: day(-365 * 2, 10, 0), createdBy: me))
        ctx.insert(KBVaccine(familyId: fid, childId: child, vaccineType: .influenza, status: .scheduled,
                             doseNumber: 1, totalDoses: 1, scheduledDate: day(14, 11, 0), reminderOn: true, createdBy: me))
        ctx.insert(KBTreatment(familyId: fid, childId: child, drugName: it ? "Vitamina D" : "Vitamin D",
                               dosageValue: 4, dosageUnit: it ? "gocce" : "drops", isLongTerm: true,
                               startDate: day(-20, 8, 0), scheduleTimes: ["08:00"], reminderEnabled: true, createdBy: me))

        // Documenti
        let folders = it ? ["Scuola", "Casa", "Salute", "Auto"] : ["School", "Home", "Health", "Car"]
        let cats = folders.enumerated().map { i, name in
            KBDocumentCategory(id: "demo-doc-cat-\(i)", familyId: fid, title: name, sortOrder: i, updatedBy: me)
        }
        cats.forEach { ctx.insert($0) }
        let docs: [(String, Int, Int)] = it
            ? [("Pagella primo quadrimestre", 0, -12), ("Autorizzazione gita al museo", 0, -2),
               ("Contratto di affitto", 1, -200), ("Bolletta luce ottobre", 1, -6),
               ("Libretto vaccinale di Marco", 2, -30), ("Referto visita pediatrica", 2, -20),
               ("Polizza auto 2026", 3, -90), ("Libretto di circolazione", 3, -400)]
            : [("School report, first term", 0, -12), ("Museum trip permission slip", 0, -2),
               ("Rental agreement", 1, -200), ("October electricity bill", 1, -6),
               ("Marco's vaccination record", 2, -30), ("Paediatric visit report", 2, -20),
               ("Car insurance 2026", 3, -90), ("Vehicle registration", 3, -400)]
        for (title, cat, daysAgo) in docs {
            ctx.insert(KBDocument(familyId: fid, childId: nil, categoryId: cats[cat].id, title: title,
                                  fileName: "\(title).pdf", mimeType: "application/pdf",
                                  fileSize: Int64(180_000 + title.count * 4_000), storagePath: "", downloadURL: nil,
                                  createdBy: me, updatedBy: me, createdAt: day(daysAgo, 18, 0), updatedAt: day(daysAgo, 18, 0)))
        }

        // Chat
        let chat: [(String, String, String?, Int, Int, (Double, Double)?)] = it
            ? [(partner, "Luca", "Esco ora dall'ufficio, prendo io Marco a nuoto", 16, 5, nil),
               (me, "Anna", "Perfetto! Nella borsa c'è già l'accappatoio", 16, 7, nil),
               (grandmaUid, "Nonna Giulia", "Stasera vi aspetto a cena, faccio le lasagne", 16, 20, nil),
               (me, "Anna", "Arriviamo verso le 20!", 16, 22, nil),
               (partner, "Luca", nil, 17, 2, (45.4689, 9.1747)),
               (partner, "Luca", "Siamo in piscina, Marco è già in acqua", 17, 3, nil)]
            : [(partner, "Luca", "Leaving the office now, I'll take Marco to swimming", 16, 5, nil),
               (me, "Anna", "Perfect! His bathrobe is already in the bag", 16, 7, nil),
               (grandmaUid, "Grandma Giulia", "Dinner at mine tonight, I'm making lasagne", 16, 20, nil),
               (me, "Anna", "We'll be there around 8!", 16, 22, nil),
               (partner, "Luca", nil, 17, 2, (45.4689, 9.1747)),
               (partner, "Luca", "We're at the pool, Marco is already in the water", 17, 3, nil)]
        // Orari relativi ad adesso: l'ultimo messaggio è di pochi minuti fa.
        let lastMinutes = (chat.last?.3 ?? 17) * 60 + (chat.last?.4 ?? 3)
        for (sender, name, text, h, m, loc) in chat {
            let minutesAgo = lastMinutes - (h * 60 + m) + 4
            ctx.insert(KBChatMessage(familyId: fid, senderId: sender, senderName: name,
                                     type: loc == nil ? .text : .location, text: text,
                                     latitude: loc?.0, longitude: loc?.1,
                                     createdAt: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60))))
        }

        // Viaggio con l'itinerario
        let trip = KBTrip(id: "demo-trip", familyId: fid, name: it ? "Toscana in famiglia" : "Family trip to Tuscany",
                          startDate: day(30, 9, 0), endDate: day(33, 18, 0),
                          participantIdsJson: "[\"\(me)\",\"\(partner)\",\"\(child)\"]",
                          budgetTotal: 1200, createdBy: me)
        ctx.insert(trip)
        ctx.insert(KBTripLeg(familyId: fid, tripId: trip.id, order: 0, fromLocation: "Milano", toLocation: "Firenze",
                             transportModeRaw: "train"))
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let days: [(String, String, String, String)] = it
            ? [("Firenze", "Arrivo in treno e passeggiata fino a Ponte Vecchio", "Giardino di Boboli, con il labirinto per Marco", "Cena in trattoria in Oltrarno"),
               ("Firenze", "Museo Galileo: esperimenti a misura di bambino", "Gelato e giro in carrozza in piazza della Signoria", "Tramonto da piazzale Michelangelo"),
               ("San Gimignano", "Le torri e il centro storico", "Picnic nelle colline e fattoria con gli animali", "Agriturismo con piscina"),
               ("Siena", "Piazza del Campo e il Duomo", "Laboratorio di ceramica per famiglie", "Rientro a Milano in treno")]
            : [("Florence", "Arrive by train and walk to Ponte Vecchio", "Boboli Gardens, with the maze for Marco", "Dinner at a trattoria in Oltrarno"),
               ("Florence", "Galileo Museum: experiments for kids", "Gelato and a carriage ride in Piazza della Signoria", "Sunset from Piazzale Michelangelo"),
               ("San Gimignano", "The towers and the old town", "Picnic in the hills and a farm with animals", "Farm stay with a pool"),
               ("Siena", "Piazza del Campo and the Cathedral", "Family pottery workshop", "Train back to Milan")]
        for (i, d) in days.enumerated() {
            ctx.insert(KBTripDayPlan(familyId: fid, tripId: trip.id, dateString: fmt.string(from: day(30 + i, 9, 0)),
                                     location: d.0, morningPlan: d.1, afternoonPlan: d.2, eveningPlan: d.3))
        }

        // Il questionario dei viaggi è già fatto: la sezione apre l'elenco.
        UserDefaults.standard.set(true, forKey: "travelOnboardingCompleted.\(me)")

        // Password, cifrate davvero con una chiave di famiglia della demo
        if FamilyKeychainStore.loadFamilyKey(familyId: fid, userId: me) == nil {
            try? FamilyKeychainStore.saveFamilyKey(SymmetricKey(size: .bits256), familyId: fid, userId: me)
        }
        let passwords: [(String, String, String, String, Bool)] = [
            ("Netflix", "famiglia.rossi@example.com", "netflix.com", "Gx7!pRt2vQ", true),
            (it ? "Wi-Fi di casa" : "Home Wi-Fi", "Rossi-Casa", "", "Lasagne2026!", true),
            (it ? "Registro elettronico" : "School portal", "anna.rossi", "scuola.example.it", "Q4m#Ls9wTz", false),
            (it ? "Luce e gas" : "Energy supplier", "anna.rossi@example.com", "energia.example.it", "Ve8$nB3kRw", false),
            ("Amazon", "famiglia.rossi@example.com", "amazon.it", "Zt5@cH8pLx", false),
            (it ? "Pediatra online" : "Paediatrician portal", "marco.rossi", "salute.example.it", "Pk2!dW7mYs", false),
        ]
        let vis = KBVisibilityScope.family
        func seal(_ s: String) -> Data? {
            try? PasswordCypher.encrypt(s, familyId: fid, visibility: vis, createdBy: me, familyKeyUserId: me)
        }
        for (i, p) in passwords.enumerated() {
            guard let title = seal(p.0), let secret = seal(p.3) else { continue }
            ctx.insert(PasswordEntry(familyId: fid, createdBy: me, visibility: vis, titleCipher: title,
                                     usernameCipher: seal(p.1), passwordCipher: secret,
                                     websiteCipher: p.2.isEmpty ? nil : seal(p.2),
                                     lastUsedAt: day(-i, 20, 0), isFavorite: p.4))
        }

        // Notizie accese per la famiglia, su Milano
        UserDefaults.standard.set([
            "enabled": true,
            "lang": it ? "it" : "en",
            "place": ["countryCode": "IT", "country": "Italia", "region": "Lombardia", "province": "Milano", "city": "Milano"],
        ], forKey: "kb.news.family.\(fid)")
    }

    @MainActor
    static func wipeSections(_ ctx: ModelContext) {
        func delete<T: PersistentModel>(_ type: T.Type) {
            if let all = try? ctx.fetch(FetchDescriptor<T>()) { all.forEach { ctx.delete($0) } }
        }
        delete(KBMedicalVisit.self); delete(KBVaccine.self); delete(KBTreatment.self)
        delete(KBDocument.self); delete(KBDocumentCategory.self); delete(KBChatMessage.self)
        delete(KBTrip.self); delete(KBTripLeg.self); delete(KBTripDayPlan.self); delete(PasswordEntry.self)
    }

    // MARK: - Dati del server, finti

    /// Le posizioni degli altri membri (in app arrivano da Firestore).
    static func sharedLocations() -> [SharedUserLocation] {
        let it = demoLang == "it"
        let now = Date()
        return [
            SharedUserLocation(id: "demo-luca", name: "Luca", latitude: 45.4689, longitude: 9.1747,
                               mode: .realtime, expiresAt: nil, avatarURL: nil, batteryLevel: 68, isCharging: false,
                               lastUpdateAt: now.addingTimeInterval(-60)),
            SharedUserLocation(id: grandmaUid, name: it ? "Nonna Giulia" : "Grandma Giulia", latitude: 45.4773, longitude: 9.1815,
                               mode: .temporary, expiresAt: now.addingTimeInterval(2 * 3600), avatarURL: nil,
                               batteryLevel: 91, isCharging: true, lastUpdateAt: now.addingTimeInterval(-300)),
        ]
    }

    /// Un'edizione delle Notizie su Milano (in app la scrive il server).
    static func newsFeed() -> NewsFeed? {
        let it = demoLang == "it"
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let inDays: (Int) -> String = { fmt.string(from: Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date()) }
        func item(_ cat: String, _ level: String, _ title: String, _ summary: String, _ action: String?,
                  _ keyDate: String?, _ kind: String?, _ source: String, _ n: Int) -> [String: Any] {
            var d: [String: Any] = ["category": cat, "level": level, "title": title, "summary": summary,
                                    "publishedAt": today, "source": source, "url": "https://example.com/kidbox-demo/\(n)"]
            if let action { d["action"] = action }
            if let keyDate { d["keyDate"] = keyDate }
            if let kind { d["keyDateKind"] = kind }
            return d
        }
        let items: [[String: Any]] = it ? [
            item("bonus", "country", "Assegno unico: domande di rinnovo entro febbraio",
                 "Chi ha già l'assegno deve aggiornare l'ISEE per non ricevere l'importo minimo da marzo.",
                 "Aggiorna l'ISEE dal CAF o online", inDays(40), "deadline", "INPS", 1),
            item("school", "country", "Iscrizioni alla scuola secondaria: si apre la finestra online",
                 "Le domande per il prossimo anno si presentano sulla piattaforma del ministero, con lo SPID di un genitore.",
                 nil, inDays(75), "deadline", "Ministero dell'Istruzione", 2),
            item("health", "region", "Vaccino antinfluenzale gratuito per i bambini",
                 "In Lombardia la vaccinazione è gratuita dai 6 mesi ai 6 anni: si prenota dal pediatra o in farmacia.",
                 "Chiedi al pediatra di Marco", nil, nil, "Regione Lombardia", 3),
            item("economy", "region", "Bollette: da novembre cambia il prezzo di riferimento",
                 "Per chi è nel servizio a tutele graduali il costo dell'energia segue il mercato del mese.",
                 nil, nil, nil, "ARERA", 4),
            item("leisure", "city", "Domeniche al museo gratis per le famiglie",
                 "La prima domenica del mese i musei civici di Milano sono gratuiti, con laboratori per bambini.",
                 nil, inDays(9), "event", "Comune di Milano", 5),
            item("growth", "city", "Corsi di nuoto invernali: iscrizioni aperte",
                 "Le piscine comunali aprono i corsi per bambini dai 4 ai 12 anni, con sconto per il secondo figlio.",
                 nil, inDays(6), "deadline", "Milanosport", 6),
        ] : [
            item("bonus", "country", "Child benefit: renewal applications by February",
                 "Families already receiving it need to update their means test to avoid the minimum amount from March.",
                 "Update your means test online", inDays(40), "deadline", "INPS", 1),
            item("school", "country", "Secondary school enrolment opens online",
                 "Applications for next year go through the ministry's platform, using a parent's digital ID.",
                 nil, inDays(75), "deadline", "Ministry of Education", 2),
            item("health", "region", "Free flu vaccine for children",
                 "In Lombardy the flu jab is free from 6 months to 6 years: book with your paediatrician or a pharmacy.",
                 "Ask Marco's paediatrician", nil, nil, "Lombardy Region", 3),
            item("economy", "region", "Energy bills: the reference price changes in November",
                 "On the gradual-protection service, the energy cost now follows the monthly market price.",
                 nil, nil, nil, "ARERA", 4),
            item("leisure", "city", "Free museum Sundays for families",
                 "On the first Sunday of the month Milan's civic museums are free, with workshops for children.",
                 nil, inDays(9), "event", "City of Milan", 5),
            item("growth", "city", "Winter swimming courses: enrolment open",
                 "City pools open courses for children aged 4 to 12, with a discount for the second child.",
                 nil, inDays(6), "deadline", "Milanosport", 6),
        ]
        let events: [[String: Any]] = [
            ["title": it ? "Festa d'autunno al parco Sempione" : "Autumn party at Parco Sempione",
             "summary": it ? "Laboratori, merenda e giochi per bambini" : "Workshops, snacks and games for kids",
             "place": "Milano", "distanceKm": 2, "startDate": inDays(2), "free": true, "source": "Comune di Milano",
             "url": "https://example.com/kidbox-demo/e1"],
            ["title": it ? "Mostra sui dinosauri al Museo di Storia Naturale" : "Dinosaur exhibition at the Natural History Museum",
             "summary": it ? "Percorso per famiglie con scheletri a grandezza naturale" : "Family trail with life-size skeletons",
             "place": "Milano", "distanceKm": 3, "startDate": inDays(4), "endDate": inDays(60), "free": false,
             "source": "Museo di Storia Naturale", "url": "https://example.com/kidbox-demo/e2"],
        ]
        let raw: [String: Any] = [
            "status": "ready", "pending": [], "dateKey": today,
            "place": ["city": "Milano", "region": "Lombardia", "country": "Italia"],
            "items": items, "events": events,
            "editions": ["country": ["status": "ready", "stale": false], "local": ["status": "ready", "stale": false]],
            "charge": ["units": 0, "totalUnits": 0],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder().decode(NewsFeed.self, from: data)
    }
}
#endif
