//
//  KBDemoSeed.swift
//  KidBox
//
//  Solo build di sviluppo. Con l'argomento di lancio `-KBDemoSeed` riempie il
//  database locale con una famiglia inventata («Famiglia Rossi») e la fissa come
//  famiglia attiva: la Home si apre senza login (`RootGateView` guarda solo che
//  ci sia una famiglia in SwiftData) e si possono fare gli screenshot per le
//  schede degli store senza toccare dati veri.
//
//  `-KBDemoLang it|en|es|fr` sceglie la lingua dei contenuti inventati.
//  `-KBDemoHero <file>` usa quell'immagine come foto della famiglia.
//  `-KBDemoAvatar <file>` usa quell'immagine come foto profilo.
//  `-KBDemoReset` cancella prima i dati locali della demo e li rifà.
//  `-KBDemoSection <sezione>` parte su quella voce della barra laterale
//  (`SidebarSection.rawValue`: calendar, todo, expenses, assistant…).
//  `-KBDemoPush` con `-KBDemoSection`: apre la sezione sopra la Home, per la
//  barra in basso (Duo chiuso).
//  `-KBDemoLandscape` mette l'interfaccia in orizzontale (iPad, iPhone Duo
//  aperto): senza Simulator.app il simulatore non si gira.
//  Non esiste in Release: tutto sta dentro `#if DEBUG`.
//

#if DEBUG
import Foundation
import SwiftData
import UIKit

enum KBDemoSeed {

    /// Vedi `-KBDemoLandscape` in testa al file.
    @MainActor
    static func applyLandscapeIfRequested() async {
        guard CommandLine.arguments.contains("-KBDemoSeed"),
              CommandLine.arguments.contains("-KBDemoLandscape") else { return }
        try? await Task.sleep(for: .milliseconds(600))
        AppOrientation.forceForDemo(.landscapeRight)
    }

    static let familyId = "demo-rossi"
    static let meUid = "demo-anna"
    private static let me = meUid
    private static let partner = "demo-luca"
    private static let childId = "demo-marco"

    private struct Texts {
        let family: String
        let listHome: String, listMarco: String
        let events: [(title: String, place: String?, day: Int, hour: Int, minutes: Int, cat: KBEventCategory, weekly: Bool)]
        let todos: [(title: String, list: Int, assignee: String?, dueDay: Int?, done: Bool, urgent: Bool)]
        let categories: [(name: String, icon: String, hex: String)]
        let expenses: [(title: String, amount: Double, cat: Int, daysAgo: Int)]
        let groceries: [(name: String, qty: Int?)]
        let notes: [(title: String, body: String)]
    }

    private static func texts(_ lang: String) -> Texts {
        switch lang {
        case "en":
            return Texts(
                family: "The Rossi Family", listHome: "Home", listMarco: "Marco",
                events: [
                    ("Marco's swimming", "City pool", 0, 17, 0, .children, true),
                    ("Parents' meeting", "Primary school", 0, 18, 30, .school, false),
                    ("Marco's paediatrician", "Dr. Bianchi", 2, 9, 15, .health, false),
                    ("Dinner at grandma's", nil, 0, 20, 0, .family, false),
                    ("Birthday party: Giulia", "Park Villa Borghese", 5, 16, 0, .leisure, false),
                    ("Guitar lesson", "Music school", 1, 16, 0, .children, true),
                    ("Teacher meeting", "Primary school", 4, 17, 30, .school, false),
                    ("Dentist appointment", "Verdi Clinic", 6, 11, 0, .health, false),
                    ("Day at the lake", "Lake Garda", 8, 9, 30, .leisure, false),
                    ("Grandma's birthday", nil, 9, 13, 0, .family, false),
                ],
                todos: [
                    ("Buy Giulia's birthday present", 1, partner, 3, false, false),
                    ("Sign the school trip form", 1, me, 1, false, true),
                    ("Book the car service", 0, partner, 6, false, false),
                    ("Pay the electricity bill", 0, me, 2, false, false),
                    ("Pick up the swimming bag", 1, me, nil, true, false),
                    ("Pack the school trip bag", 1, me, 7, false, false),
                    ("Renew the swimming membership", 1, partner, 5, false, false),
                    ("Call the plumber", 0, me, 4, false, false),
                    ("Order grandma's cake", 0, partner, 8, false, false),
                ],
                categories: [("Groceries", "cart.fill", "#34C759"), ("School", "backpack.fill", "#FF9500"), ("Health", "cross.case.fill", "#FF3B30"), ("Home", "house.fill", "#5856D6")],
                expenses: [("Supermarket", 86.40, 0, 1), ("School canteen", 48.00, 1, 3), ("Pharmacy", 23.90, 2, 5), ("Electricity bill", 74.20, 3, 8)],
                groceries: [("Milk", 2), ("Bread", nil), ("Apples", 6), ("Pasta", 3)],
                notes: [
                    ("Christmas gift ideas", "Lego for Marco\nScarf for grandma\nCookbook for Luca\nPerfume for Anna"),
                    ("Weekly menu", "Monday: tomato pasta\nTuesday: omelette and salad\nWednesday: chicken and potatoes\nThursday: rice and courgettes\nFriday: family pizza night"),
                    ("Useful numbers", "Paediatrician, Dr. Bianchi: 02 555 0101\nSchool: 02 555 0188\nPlumber Mario: 333 555 0142"),
                    ("Lake trip packing list", "Swimsuits and towels\nSunscreen\nToys for Marco\nCamera"),
                ]
            )
        case "es":
            return Texts(
                family: "Familia Rossi", listHome: "Casa", listMarco: "Marco",
                events: [
                    ("Natación de Marco", "Piscina municipal", 0, 17, 0, .children, true),
                    ("Reunión de padres", "Colegio", 0, 18, 30, .school, false),
                    ("Pediatra de Marco", "Dr. Bianchi", 2, 9, 15, .health, false),
                    ("Cena en casa de la abuela", nil, 0, 20, 0, .family, false),
                    ("Cumpleaños de Giulia", "Parque del Retiro", 5, 16, 0, .leisure, false),
                    ("Clase de guitarra", "Escuela de música", 1, 16, 0, .children, true),
                    ("Tutoría con la maestra", "Colegio", 4, 17, 30, .school, false),
                    ("Cita con el dentista", "Clínica Verdi", 6, 11, 0, .health, false),
                    ("Excursión al lago", "Lago de Garda", 8, 9, 30, .leisure, false),
                    ("Cumpleaños de la abuela", nil, 9, 13, 0, .family, false),
                ],
                todos: [
                    ("Comprar el regalo de Giulia", 1, partner, 3, false, false),
                    ("Firmar la autorización de la excursión", 1, me, 1, false, true),
                    ("Reservar la revisión del coche", 0, partner, 6, false, false),
                    ("Pagar la factura de la luz", 0, me, 2, false, false),
                    ("Recoger la bolsa de natación", 1, me, nil, true, false),
                    ("Preparar la mochila de la excursión", 1, me, 7, false, false),
                    ("Renovar el abono de la piscina", 1, partner, 5, false, false),
                    ("Llamar al fontanero", 0, me, 4, false, false),
                    ("Encargar la tarta de la abuela", 0, partner, 8, false, false),
                ],
                categories: [("Compra", "cart.fill", "#34C759"), ("Colegio", "backpack.fill", "#FF9500"), ("Salud", "cross.case.fill", "#FF3B30"), ("Casa", "house.fill", "#5856D6")],
                expenses: [("Supermercado", 86.40, 0, 1), ("Comedor escolar", 48.00, 1, 3), ("Farmacia", 23.90, 2, 5), ("Factura de la luz", 74.20, 3, 8)],
                groceries: [("Leche", 2), ("Pan", nil), ("Manzanas", 6), ("Pasta", 3)],
                notes: [
                    ("Ideas de regalos de Navidad", "Lego para Marco\nBufanda para la abuela\nLibro de cocina para Luca\nPerfume para Anna"),
                    ("Menú de la semana", "Lunes: pasta al tomate\nMartes: tortilla y ensalada\nMiércoles: pollo y patatas\nJueves: arroz y calabacín\nViernes: pizza en familia"),
                    ("Teléfonos útiles", "Pediatra, Dr. Bianchi: 02 555 0101\nColegio: 02 555 0188\nFontanero Mario: 333 555 0142"),
                    ("Maleta para el lago", "Bañadores y toallas\nCrema solar\nJuguetes para Marco\nCámara de fotos"),
                ]
            )
        case "fr":
            return Texts(
                family: "Famille Rossi", listHome: "Maison", listMarco: "Marco",
                events: [
                    ("Natation de Marco", "Piscine municipale", 0, 17, 0, .children, true),
                    ("Réunion de parents", "École primaire", 0, 18, 30, .school, false),
                    ("Pédiatre de Marco", "Dr Bianchi", 2, 9, 15, .health, false),
                    ("Dîner chez mamie", nil, 0, 20, 0, .family, false),
                    ("Anniversaire de Giulia", "Parc Monceau", 5, 16, 0, .leisure, false),
                    ("Cours de guitare", "École de musique", 1, 16, 0, .children, true),
                    ("Rendez-vous avec la maîtresse", "École primaire", 4, 17, 30, .school, false),
                    ("Rendez-vous chez le dentiste", "Cabinet Verdi", 6, 11, 0, .health, false),
                    ("Sortie au lac", "Lac d'Annecy", 8, 9, 30, .leisure, false),
                    ("Anniversaire de mamie", nil, 9, 13, 0, .family, false),
                ],
                todos: [
                    ("Acheter le cadeau de Giulia", 1, partner, 3, false, false),
                    ("Signer l'autorisation de sortie", 1, me, 1, false, true),
                    ("Réserver la révision de la voiture", 0, partner, 6, false, false),
                    ("Payer la facture d'électricité", 0, me, 2, false, false),
                    ("Récupérer le sac de piscine", 1, me, nil, true, false),
                    ("Préparer le sac pour la sortie", 1, me, 7, false, false),
                    ("Renouveler l'abonnement de piscine", 1, partner, 5, false, false),
                    ("Appeler le plombier", 0, me, 4, false, false),
                    ("Commander le gâteau de mamie", 0, partner, 8, false, false),
                ],
                categories: [("Courses", "cart.fill", "#34C759"), ("École", "backpack.fill", "#FF9500"), ("Santé", "cross.case.fill", "#FF3B30"), ("Maison", "house.fill", "#5856D6")],
                expenses: [("Supermarché", 86.40, 0, 1), ("Cantine", 48.00, 1, 3), ("Pharmacie", 23.90, 2, 5), ("Facture d'électricité", 74.20, 3, 8)],
                groceries: [("Lait", 2), ("Pain", nil), ("Pommes", 6), ("Pâtes", 3)],
                notes: [
                    ("Idées de cadeaux de Noël", "Lego pour Marco\nÉcharpe pour mamie\nLivre de cuisine pour Luca\nParfum pour Anna"),
                    ("Menu de la semaine", "Lundi : pâtes à la tomate\nMardi : omelette et salade\nMercredi : poulet et pommes de terre\nJeudi : riz et courgettes\nVendredi : pizza en famille"),
                    ("Numéros utiles", "Pédiatre, Dr Bianchi : 02 555 0101\nÉcole : 02 555 0188\nPlombier Mario : 333 555 0142"),
                    ("Valise pour le lac", "Maillots et serviettes\nCrème solaire\nJouets pour Marco\nAppareil photo"),
                ]
            )
        default:
            return Texts(
                family: "Famiglia Rossi", listHome: "Casa", listMarco: "Marco",
                events: [
                    ("Nuoto di Marco", "Piscina comunale", 0, 17, 0, .children, true),
                    ("Riunione genitori", "Scuola primaria", 0, 18, 30, .school, false),
                    ("Pediatra di Marco", "Dott. Bianchi", 2, 9, 15, .health, false),
                    ("Cena dalla nonna", nil, 0, 20, 0, .family, false),
                    ("Festa di compleanno di Giulia", "Parco Sempione", 5, 16, 0, .leisure, false),
                    ("Lezione di chitarra", "Scuola di musica", 1, 16, 0, .children, true),
                    ("Colloquio con la maestra", "Scuola primaria", 4, 17, 30, .school, false),
                    ("Visita dal dentista", "Studio Verdi", 6, 11, 0, .health, false),
                    ("Gita al lago", "Lago di Garda", 8, 9, 30, .leisure, false),
                    ("Compleanno della nonna", nil, 9, 13, 0, .family, false),
                ],
                todos: [
                    ("Comprare il regalo per Giulia", 1, partner, 3, false, false),
                    ("Firmare l'autorizzazione per la gita", 1, me, 1, false, true),
                    ("Prenotare il tagliando dell'auto", 0, partner, 6, false, false),
                    ("Pagare la bolletta della luce", 0, me, 2, false, false),
                    ("Ritirare la borsa della piscina", 1, me, nil, true, false),
                    ("Preparare lo zaino per la gita", 1, me, 7, false, false),
                    ("Rinnovare l'abbonamento della piscina", 1, partner, 5, false, false),
                    ("Chiamare l'idraulico", 0, me, 4, false, false),
                    ("Ordinare la torta per la nonna", 0, partner, 8, false, false),
                ],
                categories: [("Spesa", "cart.fill", "#34C759"), ("Scuola", "backpack.fill", "#FF9500"), ("Salute", "cross.case.fill", "#FF3B30"), ("Casa", "house.fill", "#5856D6")],
                expenses: [("Supermercato", 86.40, 0, 1), ("Mensa scolastica", 48.00, 1, 3), ("Farmacia", 23.90, 2, 5), ("Bolletta della luce", 74.20, 3, 8)],
                groceries: [("Latte", 2), ("Pane", nil), ("Mele", 6), ("Pasta", 3)],
                notes: [
                    ("Idee regalo di Natale", "Lego per Marco\nSciarpa per la nonna\nLibro di cucina per Luca\nProfumo per Anna"),
                    ("Menù della settimana", "Lunedì: pasta al pomodoro\nMartedì: frittata e insalata\nMercoledì: pollo e patate\nGiovedì: riso e zucchine\nVenerdì: pizza in famiglia"),
                    ("Numeri utili", "Pediatra, dott. Bianchi: 02 555 0101\nScuola: 02 555 0188\nIdraulico Mario: 333 555 0142"),
                    ("Lista valigia per il lago", "Costumi e teli\nCrema solare\nGiochi per Marco\nMacchina fotografica"),
                ]
            )
        }
    }

    /// La richiesta di famiglia mostrata nella Home della demo: la manda Luca,
    /// la riceve Anna («chi prende Marco giovedì?»).
    static func demoRequest(familyId: String) -> FamilyRequest? {
        guard CommandLine.arguments.contains("-KBDemoSeed"), familyId == Self.familyId else { return nil }
        let args = CommandLine.arguments
        let lang = args.firstIndex(of: "-KBDemoLang").flatMap { i in
            args.indices.contains(i + 1) ? args[i + 1] : nil
        } ?? "it"
        let title: String
        switch lang {
        case "en": title = "Who picks Marco up on Thursday at 5pm?"
        case "es": title = "¿Quién recoge a Marco el jueves a las 17:00?"
        case "fr": title = "Qui récupère Marco jeudi à 17 h ?"
        default:   title = "Chi prende Marco giovedì alle 17?"
        }
        let cal = Calendar.current
        let thursday = cal.nextDate(after: Date(), matching: DateComponents(hour: 17, minute: 0, weekday: 5),
                                    matchingPolicy: .nextTime) ?? Date()
        return FamilyRequest(demoId: "demo-request", familyId: familyId, title: title, dueAt: thursday,
                             createdBy: partner, recipients: [me])
    }

    /// Da chiamare subito dopo la creazione del container.
    @MainActor
    static func runIfRequested(container: ModelContainer) {
        let args = CommandLine.arguments
        guard args.contains("-KBDemoSeed") else { return }
        let lang = args.firstIndex(of: "-KBDemoLang").flatMap { i in
            args.indices.contains(i + 1) ? args[i + 1] : nil
        } ?? "it"
        let ctx = container.mainContext
        let fid = familyId

        // `-KBDemoAvatar <percorso>`: foto profilo di chi usa la demo, in alto a sinistra in Home.
        if let i = args.firstIndex(of: "-KBDemoAvatar"), args.indices.contains(i + 1),
           let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1])) {
            let uid = me
            let profile = (try? ctx.fetch(FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })))?.first
                ?? KBUserProfile(uid: uid, displayName: "Anna")
            if profile.modelContext == nil { ctx.insert(profile) }
            profile.avatarData = data
            profile.updatedAt = Date()
            try? ctx.save()
        }

        let existing = (try? ctx.fetch(FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid }))) ?? []
        if !existing.isEmpty, !args.contains("-KBDemoReset") {
            UserDefaults.standard.set(fid, forKey: "KidBox.activeFamilyId")
            return
        }
        if args.contains("-KBDemoReset") { wipe(ctx, fid); wipeSections(ctx) }

        let t = texts(lang)
        let now = Date()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: startOfToday) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }

        let family = KBFamily(id: fid, name: t.family, createdBy: me, updatedBy: me,
                              createdAt: day(-60), updatedAt: now)
        let marco = KBChild(id: childId, familyId: fid, name: "Marco", birthDate: day(-365 * 8),
                            createdBy: me, createdAt: day(-60), updatedBy: me, updatedAt: now)
        family.children.append(marco)
        // `-KBDemoHero <percorso>`: foto della famiglia da un file locale.
        if let i = args.firstIndex(of: "-KBDemoHero"), args.indices.contains(i + 1) {
            family.heroPhotoURL = URL(fileURLWithPath: args[i + 1]).absoluteString
            family.heroPhotoUpdatedAt = now
        }
        ctx.insert(family)

        ctx.insert(KBFamilyMember(id: "m-\(me)", familyId: fid, userId: me, role: "owner",
                                  displayName: "Anna", updatedBy: me))
        ctx.insert(KBFamilyMember(id: "m-\(partner)", familyId: fid, userId: partner, role: "member",
                                  displayName: "Luca", updatedBy: me))

        for e in t.events {
            ctx.insert(KBCalendarEvent(
                familyId: fid, childId: childId, title: e.title, location: e.place,
                startDate: day(e.day, e.hour, e.minutes),
                endDate: day(e.day, e.hour + 1, e.minutes),
                category: e.cat, recurrence: e.weekly ? .weekly : .none,
                updatedBy: me, createdBy: me
            ))
        }

        let lists = [
            KBTodoList(id: "demo-list-home", familyId: fid, childId: childId, name: t.listHome, createdBy: me),
            KBTodoList(id: "demo-list-marco", familyId: fid, childId: childId, name: t.listMarco, createdBy: me),
        ]
        lists.forEach { ctx.insert($0) }
        for todo in t.todos {
            let item = KBTodoItem(
                familyId: fid, childId: childId, title: todo.title,
                listId: lists[todo.list].id,
                dueAt: todo.dueDay.map { day($0, 18) },
                isDone: todo.done, updatedBy: me
            )
            item.assignedTo = todo.assignee
            if todo.urgent { item.priorityRaw = 1 }
            ctx.insert(item)
        }

        let cats = t.categories.enumerated().map { i, c in
            KBExpenseCategory(id: "demo-cat-\(i)", familyId: fid, name: c.name, icon: c.icon, colorHex: c.hex, sortIndex: i)
        }
        cats.forEach { ctx.insert($0) }
        for e in t.expenses {
            ctx.insert(KBExpense(familyId: fid, title: e.title, amount: e.amount,
                                 date: day(-e.daysAgo), categoryId: cats[e.cat].id, createdByUid: me))
        }
        for (i, n) in t.notes.enumerated() {
            ctx.insert(KBNote(familyId: fid, title: n.title, body: n.body,
                              createdBy: i % 2 == 0 ? me : partner,
                              createdByName: i % 2 == 0 ? "Anna" : "Luca",
                              updatedBy: me, updatedByName: "Anna",
                              createdAt: day(-i - 1), updatedAt: day(-i - 1)))
        }
        for g in t.groceries {
            ctx.insert(KBGroceryItem(familyId: fid, name: g.name, quantity: g.qty, updatedBy: me, createdBy: me))
        }

        seedSections(ctx, day: day)

        try? ctx.save()
        UserDefaults.standard.set(fid, forKey: "KidBox.activeFamilyId")
    }

    @MainActor
    private static func wipe(_ ctx: ModelContext, _ fid: String) {
        func delete<T: PersistentModel>(_ type: T.Type) {
            if let all = try? ctx.fetch(FetchDescriptor<T>()) { all.forEach { ctx.delete($0) } }
        }
        delete(KBCalendarEvent.self); delete(KBTodoItem.self); delete(KBTodoList.self)
        delete(KBNote.self); delete(KBExpense.self); delete(KBExpenseCategory.self); delete(KBGroceryItem.self)
        delete(KBFamilyMember.self); delete(KBChild.self); delete(KBFamily.self)
        try? ctx.save()
    }
}
extension FamilyRequest {
    init(demoId: String, familyId: String, title: String, dueAt: Date?, createdBy: String, recipients: [String]) {
        self.id = demoId
        self.familyId = familyId
        self.title = title
        self.notes = nil
        self.dueAt = dueAt
        self.dueHasTime = true
        self.listId = "demo-list-marco"
        self.childId = "demo-marco"
        self.createdBy = createdBy
        self.recipients = recipients
        self.status = .open
        self.expiresAt = nil
        self.responses = []
        self.claimedByUid = nil
        self.claimedByName = nil
        self.claimedByExternal = false
        self.todoId = nil
        self.externalLabel = nil
        self.hasExternalLink = false
    }
}
#endif

import FirebaseAuth

/// L'uid dell'utente corrente. In Release è esattamente `Auth.auth().currentUser?.uid`;
/// nella build di sviluppo con `-KBDemoSeed` ricade sull'utente della famiglia
/// inventata, così le schermate filtrate per utente mostrano i dati della demo.
enum KBUid {
    static var current: String? {
        #if DEBUG
        if CommandLine.arguments.contains("-KBDemoSeed") { return Auth.auth().currentUser?.uid ?? KBDemoSeed.meUid }
        #endif
        return Auth.auth().currentUser?.uid
    }
}
