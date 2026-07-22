//
//  NudgeEngine.swift
//  KidBox
//
//  Motore dei nudge: decide COSA suggerire, QUANDO, e pianifica le notifiche.
//
//  Gira interamente sul dispositivo. Il server non sa quali feature un utente
//  non usa e non deve saperlo: quel profilo esiste solo qui, in memoria, per il
//  tempo di una valutazione, e non viene mai scritto da nessuna parte.
//
//  Le notifiche sono LOCALI e PRE-PIANIFICATE. È la proprietà che rende il
//  sistema utile proprio sull'utente che vogliamo raggiungere: una notifica
//  locale programmata scatta anche se l'app non viene mai più riaperta, mentre
//  qualsiasi logica "al prossimo avvio" non raggiungerebbe mai chi non torna.
//
//  A ogni foreground la coda viene CANCELLATA e ricalcolata da zero. Costa
//  poco ed evita l'errore peggiore: un nudge stantio che invita a fare una
//  cosa che l'utente ha già fatto ieri.
//

import Foundation
import SwiftData
import UserNotifications
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class NudgeEngine {

    static let shared = NudgeEngine()

    /// Prefisso degli identificatori: permette di cancellare SOLO i nudge
    /// senza toccare i promemoria veri (cure, scadenze), che sono di un'altra
    /// natura e che l'utente ha chiesto esplicitamente.
    static let identifierPrefix = "kb.nudge."

    /// Quanti invii futuri tenere in coda. Non serve pianificare tutto: iOS
    /// tiene al massimo 64 notifiche locali pendenti in totale, condivise con
    /// cure e scadenze, e la coda viene comunque ricalcolata a ogni apertura.
    private static let maxScheduled = 6

    private var cachedConfig: NudgeConfig?

    private init() {}

    // MARK: - Ingresso

    /// Da chiamare al passaggio in foreground.
    func refresh(modelContext: ModelContext) async {
        guard Auth.auth().currentUser != nil else { return }
        guard !NudgeState.isOptedOut else {
            await cancelAllScheduled()
            return
        }

        // Il permesso non si chiede qui: un nudge non vale una richiesta di
        // permesso a freddo. Se non c'è, non si pianifica e basta.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let config = await loadConfig()
        guard config.enabled else {
            await cancelAllScheduled()
            return
        }

        let signals = Signals(modelContext: modelContext)
        let plan = buildPlan(config: config, signals: signals)

        await cancelAllScheduled()
        for item in plan {
            await schedule(item)
        }
        KBLog.app.kbInfo("[Nudge] pianificati \(plan.count) nudge")
    }

    // MARK: - Configurazione

    /// Legge `config/nudges`, con il catalogo compilato come rete di sicurezza.
    /// Un errore qui (documento assente, permessi, campo malformato) non deve
    /// spegnere il motore: si continua con il default.
    private func loadConfig() async -> NudgeConfig {
        if let cachedConfig { return cachedConfig }
        do {
            let snap = try await Firestore.firestore()
                .collection("config").document("nudges").getDocument()
            guard let data = snap.data() else {
                cachedConfig = .builtIn
                return .builtIn
            }
            let json = try JSONSerialization.data(withJSONObject: data)
            let decoded = try JSONDecoder().decode(NudgeConfig.self, from: json)
            cachedConfig = decoded
            KBLog.app.kbInfo("[Nudge] config remota caricata, \(decoded.campaigns.count) campagne")
            return decoded
        } catch {
            KBLog.app.kbDebug("[Nudge] config remota non disponibile, uso il default: \(error.localizedDescription)")
            cachedConfig = .builtIn
            return .builtIn
        }
    }

    // MARK: - Segnali locali

    /// Fotografia dello stato dell'utente, letta dal database locale.
    /// Costruita una volta per valutazione e mai persistita.
    private struct Signals {
        let familyMembers: Int
        let unusedFeatures: Set<NudgeFeature>

        init(modelContext: ModelContext) {
            let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "activeFamilyId") ?? ""

            func count<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> Int {
                (try? modelContext.fetchCount(FetchDescriptor<T>(predicate: predicate))) ?? 0
            }

            familyMembers = count(KBFamilyMember.self, #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            })

            var unused: Set<NudgeFeature> = []
            if count(KBDocument.self, #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            }) == 0 { unused.insert(.documents) }

            if count(KBWalletTicket.self, #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            }) == 0 { unused.insert(.wallet) }

            if count(KBMedicalExam.self, #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            }) == 0 { unused.insert(.health) }

            if count(KBChatMessage.self, #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            }) == 0 { unused.insert(.chat) }

            if count(KBCalendarEvent.self, #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            }) == 0 { unused.insert(.calendar) }

            // L'AI non ha `isDeleted`: la conversazione o c'è o non c'è.
            if count(KBAIConversation.self, #Predicate {
                $0.familyId == familyId
            }) == 0 { unused.insert(.ai) }

            unusedFeatures = unused
        }
    }

    // MARK: - Pianificazione

    private struct PlannedNudge {
        let campaign: NudgeCampaign
        let fireDate: Date
    }

    /// Costruisce la coda: campagne ammissibili in ordine, distanziate dal
    /// cooldown globale, ognuna non prima di quando le sue regole permettono.
    private func buildPlan(config: NudgeConfig, signals: Signals) -> [PlannedNudge] {
        let calendar = Calendar.current
        let now = Date()

        // Tetto trimestrale: conta anche quelli già consegnati.
        let remainingQuarter = config.maxPerQuarter - NudgeState.firesInLast(days: 90)
        guard remainingQuarter > 0 else { return [] }

        // Il cursore parte dal primo istante in cui è lecito notificare
        // qualsiasi cosa: mai prima che il cooldown dall'ultimo invio sia
        // scaduto.
        var cursor = now
        if let last = NudgeState.lastFireAny,
           let earliest = calendar.date(byAdding: .day, value: config.globalCooldownDays, to: last) {
            cursor = max(cursor, earliest)
        }

        var plan: [PlannedNudge] = []

        for campaign in config.campaigns.sorted(by: { $0.order < $1.order }) {
            guard campaign.enabled else { continue }
            guard isEligible(campaign, signals: signals) else { continue }

            let alreadyFired = NudgeState.fireCount(campaignId: campaign.id)
            let remaining = campaign.maxFires - alreadyFired
            guard remaining > 0 else { continue }

            // Base della ripetizione: l'ultimo invio di QUESTA campagna se c'è
            // stato, altrimenti l'installazione più il ritardo iniziale.
            var campaignCursor: Date
            if let last = NudgeState.lastFire(campaignId: campaign.id) {
                campaignCursor = calendar.date(
                    byAdding: .day, value: campaign.repeatEveryDays, to: last) ?? cursor
            } else {
                campaignCursor = calendar.date(
                    byAdding: .day, value: campaign.firstDelayDays, to: NudgeState.installDate) ?? cursor
            }

            for _ in 0..<remaining {
                guard plan.count < Self.maxScheduled, plan.count < remainingQuarter else {
                    return plan
                }
                let fire = adjustForQuietHours(max(cursor, campaignCursor), config: config)
                plan.append(PlannedNudge(campaign: campaign, fireDate: fire))

                cursor = calendar.date(byAdding: .day, value: config.globalCooldownDays, to: fire) ?? fire
                campaignCursor = calendar.date(
                    byAdding: .day, value: campaign.repeatEveryDays, to: fire) ?? fire
            }
        }
        return plan
    }

    private func isEligible(_ campaign: NudgeCampaign, signals: Signals) -> Bool {
        let r = campaign.requires
        if let maxMembers = r.familyMembersMax, signals.familyMembers > maxMembers { return false }
        if let minMembers = r.familyMembersMin, signals.familyMembers < minMembers { return false }
        if let feature = r.featureUnused, !signals.unusedFeatures.contains(feature) { return false }
        return true
    }

    /// Sposta l'orario fuori dalla fascia silenziosa. Un suggerimento
    /// commerciale che sveglia qualcuno alle 3 di notte non viene letto: viene
    /// disattivato, e quella è una porta che non si riapre.
    private func adjustForQuietHours(_ date: Date, config: NudgeConfig) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let start = config.quietHoursStart
        let end = config.quietHoursEnd

        // Fascia che scavalca la mezzanotte (es. 21 → 9), il caso normale.
        let inQuiet = start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
        guard inQuiet else { return date }

        // Sposta alla prossima occorrenza dell'ora di fine, aggiungendo un
        // giorno se l'ora di fine di oggi è già passata.
        var target = calendar.date(bySettingHour: end, minute: 30, second: 0, of: date) ?? date
        if target <= date {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return target
    }

    // MARK: - Consegna

    private func schedule(_ item: PlannedNudge) async {
        let content = UNMutableNotificationContent()
        content.title = item.campaign.resolvedTitle
        content.body = item.campaign.resolvedBody
        content.sound = .default
        // Stesso contratto del broadcast: il testo viaggia nel payload, così la
        // view lo mostra per intero anche se il catalogo remoto è cambiato nel
        // frattempo.
        content.userInfo = [
            "type": "nudge",
            "campaignId": item.campaign.id,
            "title": item.campaign.resolvedTitle,
            "body": item.campaign.resolvedBody,
            "destination": item.campaign.destination?.rawValue ?? "",
        ]

        let interval = max(item.fireDate.timeIntervalSinceNow, 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + item.campaign.id + "." + String(Int(item.fireDate.timeIntervalSince1970)),
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            // Si registra alla PIANIFICAZIONE, non alla consegna: al momento
            // della consegna l'app può essere chiusa e non ci sarebbe nessuno
            // ad aggiornare lo stato, col risultato di ripianificare all'infinito
            // lo stesso nudge.
            NudgeState.recordFire(campaignId: item.campaign.id, at: item.fireDate)
            // `KBAnalytics` è un actor: l'hop è obbligato.
            await KBAnalytics.shared.logNudge(
                name: "nudge_scheduled", campaignId: item.campaign.id)
        } catch {
            KBLog.app.kbError("[Nudge] pianificazione fallita: \(error.localizedDescription)")
        }
    }

    /// Cancella solo i pendenti con il nostro prefisso.
    private func cancelAllScheduled() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        // Le pianificazioni cancellate vanno tolte anche dallo storico,
        // altrimenti un nudge mai consegnato consumerebbe per sempre una delle
        // occasioni della sua campagna.
        let now = Date()
        NudgeState.fires = NudgeState.fires.filter { $0.at <= now }
    }
}
