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

    /// La lingua chiesta così com'è (it, en, es, fr), per le parti tradotte
    /// in tutte e quattro.
    static var rawDemoLang: String {
        let args = CommandLine.arguments
        return args.firstIndex(of: "-KBDemoLang").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "it"
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
                                  displayName: ["it": "Nonna Giulia", "es": "Abuela Giulia", "fr": "Mamie Giulia"][rawDemoLang] ?? "Grandma Giulia", updatedBy: me))

        // Salute di Marco: anche in spagnolo e francese, per il carosello
        // della landing.
        let lang = rawDemoLang
        func t(_ it: String, _ en: String, _ es: String, _ fr: String) -> String {
            switch lang { case "it": return it; case "es": return es; case "fr": return fr; default: return en }
        }
        ctx.insert(KBMedicalVisit(id: "demo-visit-checkup", familyId: fid, childId: child, date: day(-20, 10, 0),
                                  doctorName: lang == "fr" ? "Dr Bianchi" : "Dr. Bianchi",
                                  doctorSpecialization: .pediatra,
                                  reason: t("Bilancio di salute degli 8 anni", "8-year check-up", "Revisión de los 8 años", "Bilan de santé des 8 ans"),
                                  diagnosis: t("Crescita regolare, peso e altezza nella norma", "Healthy growth, weight and height on track",
                                               "Crecimiento normal, peso y altura dentro de lo esperado", "Croissance régulière, poids et taille dans la norme"),
                                  recommendations: t("Vitamina D fino a marzo, controllo vista a scuola", "Vitamin D until March, eye test at school",
                                                     "Vitamina D hasta marzo, revisión de la vista en el colegio", "Vitamine D jusqu'en mars, contrôle de la vue à l'école"),
                                  visitStatus: .completed, createdBy: me))
        ctx.insert(KBMedicalVisit(familyId: fid, childId: child, date: day(-45, 16, 30),
                                  doctorName: t("Dr.ssa Ferri", "Dr. Ferri", "Dra. Ferri", "Dr Ferri"),
                                  doctorSpecialization: .otorinolaringoiatra,
                                  reason: t("Mal d'orecchio", "Earache", "Dolor de oído", "Mal d'oreille"),
                                  diagnosis: t("Otite media, risolta in una settimana", "Middle-ear infection, cleared in a week",
                                               "Otitis media, resuelta en una semana", "Otite moyenne, guérie en une semaine"),
                                  visitStatus: .completed, createdBy: partner))
        ctx.insert(KBMedicalVisit(familyId: fid, childId: child, date: day(2, 9, 15),
                                  doctorName: lang == "fr" ? "Dr Bianchi" : "Dr. Bianchi",
                                  doctorSpecialization: .pediatra,
                                  reason: t("Controllo dopo l'otite", "Follow-up after the ear infection",
                                            "Control después de la otitis", "Contrôle après l'otite"),
                                  visitStatus: .booked, reminderOn: true, createdBy: me))
        ctx.insert(KBVaccine(familyId: fid, childId: child, vaccineType: .esavalente, status: .administered,
                             doseNumber: 3, totalDoses: 3, administeredDate: day(-365 * 7, 10, 0), createdBy: me))
        ctx.insert(KBVaccine(familyId: fid, childId: child, vaccineType: .mpr, status: .administered,
                             doseNumber: 2, totalDoses: 2, administeredDate: day(-365 * 2, 10, 0), createdBy: me))
        ctx.insert(KBVaccine(familyId: fid, childId: child, vaccineType: .influenza, status: .scheduled,
                             doseNumber: 1, totalDoses: 1, scheduledDate: day(14, 11, 0), reminderOn: true, createdBy: me))
        ctx.insert(KBTreatment(familyId: fid, childId: child,
                               drugName: t("Vitamina D", "Vitamin D", "Vitamina D", "Vitamine D"),
                               dosageValue: 4, dosageUnit: t("gocce", "drops", "gotas", "gouttes"), isLongTerm: true,
                               startDate: day(-20, 8, 0), scheduleTimes: ["08:00"], reminderEnabled: true, createdBy: me))

        // Documenti, in tutte e quattro le lingue (carosello della landing)
        let cats = demoDocFolders.enumerated().map { i, name in
            KBDocumentCategory(id: "demo-doc-cat-\(i)", familyId: fid, title: name, sortOrder: i, updatedBy: me)
        }
        cats.forEach { ctx.insert($0) }
        let docs: [(String, Int, Int, String?)] = [
            (t("Pagella primo quadrimestre", "School report, first term", "Boletín de notas del primer trimestre", "Bulletin du premier trimestre"), 0, -12, nil),
            (t("Autorizzazione gita al museo", "Museum trip permission slip", "Autorización excursión al museo", "Autorisation sortie au musée"), 0, -2, nil),
            (t("Orario scolastico 2026-27", "School timetable 2026-27", "Horario escolar 2026-27", "Emploi du temps 2026-27"), 0, -60, nil),
            (t("Contratto di affitto", "Rental agreement", "Contrato de alquiler", "Contrat de location"), 1, -200, nil),
            (t("Bolletta luce ottobre", "October electricity bill", "Factura de la luz de octubre", "Facture d'électricité d'octobre"), 1, -6, "demo-doc-bill"),
            (t("Libretto vaccinale di Marco", "Marco's vaccination record", "Cartilla de vacunación de Marco", "Carnet de vaccination de Marco"), 2, -30, nil),
            (t("Referto visita pediatrica", "Paediatric visit report", "Informe de la visita al pediatra", "Compte rendu de la visite pédiatrique"), 2, -20, "demo-doc-report"),
            (t("Polizza auto 2026", "Car insurance 2026", "Póliza del coche 2026", "Assurance auto 2026"), 3, -90, nil),
            (t("Libretto di circolazione", "Vehicle registration", "Permiso de circulación", "Carte grise"), 3, -400, nil),
        ]
        for (title, cat, daysAgo, docId) in docs {
            ctx.insert(KBDocument(id: docId ?? UUID().uuidString, familyId: fid, childId: nil, categoryId: cats[cat].id, title: title,
                                  fileName: "\(title).pdf", mimeType: "application/pdf",
                                  fileSize: Int64(180_000 + title.count * 4_000), storagePath: "", downloadURL: nil,
                                  createdBy: me, updatedBy: me, createdAt: day(daysAgo, 18, 0), updatedAt: day(daysAgo, 18, 0)))
        }

        // Chat
        let grandma = t("Nonna Giulia", "Grandma Giulia", "Abuela Giulia", "Mamie Giulia")
        let chat: [(String, String, String?, Int, Int, (Double, Double)?)] = [
            (partner, "Luca", t("Esco ora dall'ufficio, prendo io Marco a nuoto", "Leaving the office now, I'll take Marco to swimming",
                                "Salgo ahora de la oficina, recojo yo a Marco en natación", "Je quitte le bureau, je prends Marco à la piscine"), 16, 5, nil),
            (me, "Anna", t("Perfetto! Nella borsa c'è già l'accappatoio", "Perfect! His bathrobe is already in the bag",
                           "¡Perfecto! El albornoz ya está en la bolsa", "Parfait ! Le peignoir est déjà dans le sac"), 16, 7, nil),
            (grandmaUid, grandma, t("Stasera vi aspetto a cena, faccio le lasagne", "Dinner at mine tonight, I'm making lasagne",
                                    "Esta noche os espero a cenar, hago lasaña", "Ce soir je vous attends pour dîner, je fais des lasagnes"), 16, 20, nil),
            (me, "Anna", t("Arriviamo verso le 20!", "We'll be there around 8!", "¡Llegamos sobre las 20!", "On arrive vers 20 h !"), 16, 22, nil),
            (partner, "Luca", nil, 17, 2, (45.4689, 9.1747)),
            (partner, "Luca", t("Siamo in piscina, Marco è già in acqua", "We're at the pool, Marco is already in the water",
                                "Estamos en la piscina, Marco ya está en el agua", "On est à la piscine, Marco est déjà dans l'eau"), 17, 3, nil),
        ]
        // Oggi, nel pomeriggio: per gli screenshot la barra di stato va messa
        // dopo le 17:03 (`simctl status_bar … --time 17:41`).
        for (sender, name, text, h, m, loc) in chat {
            let msg = KBChatMessage(familyId: fid, senderId: sender, senderName: name,
                                    type: loc == nil ? .text : .location, text: text,
                                    latitude: loc?.0, longitude: loc?.1, createdAt: day(0, h, m))
            msg.syncState = .synced
            ctx.insert(msg)
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
            "lang": rawDemoLang,
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
        let lang = rawDemoLang
        func t(_ it: String, _ en: String, _ es: String, _ fr: String) -> String {
            switch lang { case "it": return it; case "es": return es; case "fr": return fr; default: return en }
        }
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
        let items: [[String: Any]] = [
            item("bonus", "country", t("Assegno unico: domande di rinnovo entro febbraio",
                   "Child benefit: renewal applications by February",
                   "Asignación por hijo: renovación hasta febrero",
                   "Allocation pour enfant : renouvellement avant février"),
                 t("Chi ha già l'assegno deve aggiornare l'ISEE per non ricevere l'importo minimo da marzo.",
                   "Families already receiving it need to update their means test to avoid the minimum amount from March.",
                   "Quien ya la cobra debe actualizar el ISEE para no recibir el importe mínimo desde marzo.",
                   "Les familles qui la perçoivent doivent mettre à jour l'ISEE pour ne pas toucher le montant minimum dès mars."),
                 t("Aggiorna l'ISEE dal CAF o online",
                   "Update your means test online",
                   "Actualiza el ISEE en el CAF o en línea",
                   "Mettez à jour l'ISEE au CAF ou en ligne"), inDays(40), "deadline", t("INPS",
                   "INPS",
                   "INPS",
                   "INPS"), 1),
            item("school", "country", t("Iscrizioni alla scuola secondaria: si apre la finestra online",
                   "Secondary school enrolment opens online",
                   "Matrícula en secundaria: se abre el plazo en línea",
                   "Inscriptions au collège : la période en ligne s'ouvre"),
                 t("Le domande per il prossimo anno si presentano sulla piattaforma del ministero, con lo SPID di un genitore.",
                   "Applications for next year go through the ministry's platform, using a parent's digital ID.",
                   "Las solicitudes para el próximo curso se presentan en la plataforma del ministerio, con la identidad digital de un progenitor.",
                   "Les demandes pour l'an prochain se font sur la plateforme du ministère, avec l'identité numérique d'un parent."),
                 nil, inDays(75), "deadline", t("Ministero dell'Istruzione",
                   "Ministry of Education",
                   "Ministerio de Educación italiano",
                   "Ministère de l'Éducation italien"), 2),
            item("health", "region", t("Vaccino antinfluenzale gratuito per i bambini",
                   "Free flu vaccine for children",
                   "Vacuna de la gripe gratis para los niños",
                   "Vaccin contre la grippe gratuit pour les enfants"),
                 t("In Lombardia la vaccinazione è gratuita dai 6 mesi ai 6 anni: si prenota dal pediatra o in farmacia.",
                   "In Lombardy the flu jab is free from 6 months to 6 years: book with your paediatrician or a pharmacy.",
                   "En Lombardía la vacuna es gratuita de los 6 meses a los 6 años: se pide cita con el pediatra o en la farmacia.",
                   "En Lombardie le vaccin est gratuit de 6 mois à 6 ans : rendez-vous chez le pédiatre ou en pharmacie."),
                 t("Chiedi al pediatra di Marco",
                   "Ask Marco's paediatrician",
                   "Pregunta al pediatra de Marco",
                   "Demandez au pédiatre de Marco"), nil, nil, t("Regione Lombardia",
                   "Lombardy Region",
                   "Región de Lombardía",
                   "Région Lombardie"), 3),
            item("economy", "region", t("Bollette: da novembre cambia il prezzo di riferimento",
                   "Energy bills: the reference price changes in November",
                   "Facturas: en noviembre cambia el precio de referencia",
                   "Factures : le prix de référence change en novembre"),
                 t("Per chi è nel servizio a tutele graduali il costo dell'energia segue il mercato del mese.",
                   "On the gradual-protection service, the energy cost now follows the monthly market price.",
                   "Para quien está en el servicio de tutela gradual, el coste de la energía sigue el mercado del mes.",
                   "Pour ceux qui sont au service de protection progressive, le prix de l'énergie suit le marché du mois."),
                 nil, nil, nil, t("ARERA",
                   "ARERA",
                   "ARERA",
                   "ARERA"), 4),
            item("leisure", "city", t("Domeniche al museo gratis per le famiglie",
                   "Free museum Sundays for families",
                   "Domingos de museo gratis para las familias",
                   "Dimanches au musée gratuits pour les familles"),
                 t("La prima domenica del mese i musei civici di Milano sono gratuiti, con laboratori per bambini.",
                   "On the first Sunday of the month Milan's civic museums are free, with workshops for children.",
                   "El primer domingo de cada mes los museos municipales de Milán son gratis, con talleres para niños.",
                   "Le premier dimanche du mois, les musées municipaux de Milan sont gratuits, avec des ateliers pour enfants."),
                 nil, inDays(9), "event", t("Comune di Milano",
                   "City of Milan",
                   "Ayuntamiento de Milán",
                   "Ville de Milan"), 5),
            item("growth", "city", t("Corsi di nuoto invernali: iscrizioni aperte",
                   "Winter swimming courses: enrolment open",
                   "Cursos de natación de invierno: inscripciones abiertas",
                   "Cours de natation d'hiver : inscriptions ouvertes"),
                 t("Le piscine comunali aprono i corsi per bambini dai 4 ai 12 anni, con sconto per il secondo figlio.",
                   "City pools open courses for children aged 4 to 12, with a discount for the second child.",
                   "Las piscinas municipales abren cursos para niños de 4 a 12 años, con descuento para el segundo hijo.",
                   "Les piscines municipales ouvrent des cours pour les 4-12 ans, avec une réduction pour le deuxième enfant."),
                 nil, inDays(6), "deadline", t("Milanosport",
                   "Milanosport",
                   "Milanosport",
                   "Milanosport"), 6),
        ]
        let events: [[String: Any]] = [
            ["title": t("Festa d'autunno al parco Sempione",
                   "Autumn party at Parco Sempione",
                   "Fiesta de otoño en el parque Sempione",
                   "Fête d'automne au parc Sempione"),
             "summary": t("Laboratori, merenda e giochi per bambini",
                   "Workshops, snacks and games for kids",
                   "Talleres, merienda y juegos para niños",
                   "Ateliers, goûter et jeux pour enfants"),
             "place": "Milano", "distanceKm": 2, "startDate": inDays(2), "free": true,
             "source": t("Comune di Milano",
                   "City of Milan",
                   "Ayuntamiento de Milán",
                   "Ville de Milan"), "url": "https://example.com/kidbox-demo/e1"],
            ["title": t("Mostra sui dinosauri al Museo di Storia Naturale",
                   "Dinosaur exhibition at the Natural History Museum",
                   "Exposición de dinosaurios en el Museo de Historia Natural",
                   "Exposition sur les dinosaures au Muséum d'histoire naturelle"),
             "summary": t("Percorso per famiglie con scheletri a grandezza naturale",
                   "Family trail with life-size skeletons",
                   "Recorrido para familias con esqueletos a tamaño real",
                   "Parcours pour les familles avec des squelettes grandeur nature"),
             "place": "Milano", "distanceKm": 3, "startDate": inDays(4), "endDate": inDays(60), "free": false,
             "source": t("Museo di Storia Naturale",
                   "Natural History Museum",
                   "Museo de Historia Natural",
                   "Muséum d'histoire naturelle"), "url": "https://example.com/kidbox-demo/e2"],
            ["title": t("Letture di Natale in biblioteca",
                   "Christmas story time at the library",
                   "Lecturas de Navidad en la biblioteca",
                   "Lectures de Noël à la bibliothèque"),
             "summary": t("Storie e laboratorio per bambini dai 3 ai 7 anni",
                   "Stories and a workshop for children aged 3 to 7",
                   "Cuentos y taller para niños de 3 a 7 años",
                   "Histoires et atelier pour les 3-7 ans"),
             "place": "Monza", "distanceKm": 15, "startDate": inDays(12), "free": true,
             "source": t("Biblioteca civica di Monza",
                   "Monza public library",
                   "Biblioteca municipal de Monza",
                   "Bibliothèque municipale de Monza"), "url": "https://example.com/kidbox-demo/e3"],
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
    // MARK: - Documenti per gli screenshot

    static var demoDocFolders: [String] {
        switch rawDemoLang {
        case "it": return ["Scuola", "Casa", "Salute", "Auto"]
        case "es": return ["Colegio", "Casa", "Salud", "Coche"]
        case "fr": return ["École", "Maison", "Santé", "Voiture"]
        default: return ["School", "Home", "Health", "Car"]
        }
    }

    /// `-KBDemoDocIntel bill|report`: la scheda in cui l'assistente propone
    /// cosa fare del documento, con una risposta inventata (niente AI).
    static func demoDocIntel(_ kind: String) -> DocIntelPayload? {
        let l = rawDemoLang
        func t(_ it: String, _ en: String, _ es: String, _ fr: String) -> String {
            switch l { case "it": return it; case "es": return es; case "fr": return fr; default: return en }
        }
        let iso = ISO8601DateFormatter()
        let due = iso.string(from: Calendar.current.date(byAdding: .day, value: 15, to: Date()) ?? Date())
        var a: [[String: Any]]
        var head: (String, String)
        let docId: String
        if kind == "bill" {
            docId = "demo-doc-bill"
            head = (t("Bolletta luce", "Electricity bill", "Factura de la luz", "Facture d'électricité"),
                    t("Bolletta luce ottobre 2026", "Electricity bill, October 2026", "Factura de la luz, octubre 2026", "Facture d'électricité, octobre 2026"))
            a = [
                ["type": "expense_add", "title": head.1, "amount": 84.2, "date": due,
                 "summary": t("84,20 € in Utenze, ottobre", "€84.20 in Utilities, October", "84,20 € en Suministros, octubre", "84,20 € en Énergie, octobre")],
                ["type": "house_payment", "title": head.1, "amount": 84.2, "date": due,
                 "summary": t("Scade tra 15 giorni, addebito sul conto", "Due in 15 days, direct debit", "Vence en 15 días, domiciliada", "Échéance dans 15 jours, prélèvement")],
                ["type": "todo_add", "title": t("Controllare l'addebito della luce", "Check the electricity debit", "Comprobar el cargo de la luz", "Vérifier le prélèvement d'électricité"), "date": due,
                 "summary": t("Controllare l'addebito della luce", "Check the electricity debit", "Comprobar el cargo de la luz", "Vérifier le prélèvement d'électricité")],
                ["type": "rename_document", "renameTo": head.1,
                 "summary": t("Rinomina in «Bolletta luce ottobre 2026»", "Rename to “Electricity bill, October 2026”", "Renombrar como «Factura de la luz, octubre 2026»", "Renommer en « Facture d'électricité, octobre 2026 »")],
            ]
        } else {
            docId = "demo-doc-report"
            head = (t("Referto di visita pediatrica", "Paediatric visit report", "Informe de visita pediátrica", "Compte rendu pédiatrique"),
                    t("Bilancio di salute di Marco, 8 anni", "Marco's 8-year check-up", "Revisión de los 8 años de Marco", "Bilan de santé de Marco, 8 ans"))
            a = [
                ["type": "medical_visit", "childId": "demo-marco", "doctorName": "Dr. Bianchi",
                 "title": t("Bilancio di salute degli 8 anni", "8-year check-up", "Revisión de los 8 años", "Bilan de santé des 8 ans"),
                 "summary": t("Pediatra: crescita regolare, peso e altezza nella norma", "Paediatrician: healthy growth, weight and height on track", "Pediatra: crecimiento normal, peso y altura correctos", "Pédiatre : croissance régulière, poids et taille dans la norme")],
                ["type": "treatment_add", "childId": "demo-marco", "title": t("Vitamina D", "Vitamin D", "Vitamina D", "Vitamine D"),
                 "dosageValue": 4, "dosageUnit": t("gocce", "drops", "gotas", "gouttes"), "dailyFrequency": 1,
                 "summary": t("Vitamina D, 4 gocce al giorno fino a marzo", "Vitamin D, 4 drops a day until March", "Vitamina D, 4 gotas al día hasta marzo", "Vitamine D, 4 gouttes par jour jusqu'en mars")],
                ["type": "health_reminder", "childId": "demo-marco", "date": due,
                 "title": t("Controllo della vista", "Eye test", "Revisión de la vista", "Contrôle de la vue"),
                 "summary": t("Controllo della vista a scuola", "Eye test at school", "Revisión de la vista en el colegio", "Contrôle de la vue à l'école")],
                ["type": "rename_document", "renameTo": head.1,
                 "summary": t("Rinomina in «Bilancio di salute di Marco, 8 anni»", "Rename to “Marco's 8-year check-up”", "Renombrar como «Revisión de los 8 años de Marco»", "Renommer en « Bilan de santé de Marco, 8 ans »")],
            ]
        }
        let json: [String: Any] = ["documentType": head.0, "suggestedTitle": head.1, "actions": a]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let result = try? JSONDecoder().decode(DocIntelResult.self, from: data) else { return nil }
        return DocIntelPayload(result: result, documentId: docId,
                               children: [.init(id: "demo-marco", name: "Marco")], vehicles: [])
    }
}
#endif
