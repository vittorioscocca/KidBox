//
//  SyncCenter+AIChat.swift
//  KidBox
//
//  Sincronizzazione cross-device delle conversazioni AI (private per-utente).
//
//  Strategia:
//  - Le chat AI vivono sotto `users/{uid}/aiConversations` → visibili solo sui
//    dispositivi dello stesso utente.
//  - Merge a livello di conversazione con Last-Writer-Wins su `updatedAt`:
//    il device che ha l'ultima modifica detta l'intero set di messaggi. Questo
//    propaga correttamente anche "pulisci chat" e la compattazione (summary).
//  - Identità stabile: le conversazioni si appaiano per (visitId, providerRaw),
//    non per id locale (che è casuale per device).
//

import Foundation
import SwiftData
import Combine
import FirebaseAuth
import FirebaseFirestore

extension SyncCenter {

    // MARK: - Change publisher

    /// Notifica le chat AI aperte che lo storico è cambiato (sync inbound),
    /// così possono ricaricare i messaggi dalla SwiftData.
    private static let _aiChatChanged = PassthroughSubject<Void, Never>()

    /// Publisher osservabile dai ViewModel delle chat AI.
    var aiChatChanged: AnyPublisher<Void, Never> {
        Self._aiChatChanged.eraseToAnyPublisher()
    }


    // MARK: - Listener lifecycle

    /// Avvia il listener realtime delle conversazioni AI dell'utente corrente e
    /// riconcilia lo storico esistente (pull + backfill).
    func startAIChatRealtime(modelContext: ModelContext) {
        guard Auth.auth().currentUser?.uid != nil else {
            KBLog.sync.kbDebug("startAIChatRealtime skipped: not authenticated")
            return
        }
        KBLog.sync.kbInfo("startAIChatRealtime")
        stopAIChatRealtime()

        // 1) Riconciliazione una-tantum: pull remoto + backfill dello storico locale.
        Task { [weak self] in
            await self?.reconcileAIChat(modelContext: modelContext)
        }

        // 2) Listener realtime per gli aggiornamenti successivi.
        aiChatListener = aiChatRemote.listenConversations(
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyAIChatInbound(changes: changes, modelContext: modelContext)
            },
            onError: { err in
                KBLog.sync.kbError("[aiChat][listener] err=\(err.localizedDescription)")
            }
        )
    }

    func stopAIChatRealtime() {
        if aiChatListener != nil {
            KBLog.sync.kbInfo("stopAIChatRealtime")
        }
        aiChatListener?.remove()
        aiChatListener = nil
    }

    // MARK: - Outbound push

    /// Marca la conversazione come modificata e la carica su Firestore (best-effort).
    /// Da chiamare dopo ogni mutazione (nuovo messaggio, clear, compattazione).
    func pushAIConversation(_ conversation: KBAIConversation, modelContext: ModelContext) {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.sync.kbDebug("pushAIConversation skipped: not authenticated")
            return
        }
        conversation.ownerUserId = uid
        conversation.updatedAt = Date()
        try? modelContext.save()

        Task { [weak self] in
            do {
                try await self?.aiChatRemote.upsert(conversation: conversation)
            } catch {
                KBLog.sync.kbError("[aiChat][push] FAIL err=\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reconcile (pull + backfill)

    private func reconcileAIChat(modelContext: ModelContext) async {
        do {
            let remote = try await aiChatRemote.fetchAll()
            KBLog.sync.kbInfo("[aiChat][reconcile] remote=\(remote.count)")

            // 2a) Applica il remoto in locale (union-merge): dopo questo passo
            //     ogni conversazione locale contiene l'unione (locale ∪ remoto).
            applyAIChatInbound(changes: remote.map { .upsert($0) }, modelContext: modelContext)

            // 2b) Backfill: ricarica su Firestore tutte le conversazioni locali
            //     non vuote. Poiché ora il locale è il superset, il push (che
            //     sostituisce l'array messaggi) NON perde nulla e allinea il
            //     remoto all'unione completa.
            let remoteKeys = Set(remote.map { Self.aiKey(visitId: $0.visitId, providerRaw: $0.providerRaw) })

            let locals = try modelContext.fetch(FetchDescriptor<KBAIConversation>())
            for convo in locals where !convo.messages.isEmpty {
                let key = Self.aiKey(visitId: convo.visitId, providerRaw: convo.providerRaw)
                // Se il remoto non ha questa conversazione, garantiamo un updatedAt
                // valido così il LWW dei campi summary funziona sugli altri device.
                if !remoteKeys.contains(key), convo.updatedAt == .distantPast {
                    convo.updatedAt = Date()
                }
                do {
                    let uid = Auth.auth().currentUser?.uid ?? ""
                    if convo.ownerUserId.isEmpty { convo.ownerUserId = uid }
                    try await aiChatRemote.upsert(conversation: convo)
                    KBLog.sync.kbDebug("[aiChat][backfill] pushed key=\(key) msgs=\(convo.messages.count)")
                } catch {
                    KBLog.sync.kbError("[aiChat][backfill] FAIL key=\(key) err=\(error.localizedDescription)")
                }
            }
            try? modelContext.save()
        } catch {
            KBLog.sync.kbError("[aiChat][reconcile] FAIL err=\(error.localizedDescription)")
        }
    }

    // MARK: - Inbound apply (union-merge, non distruttivo)
    //
    // IMPORTANTE: lo storico non deve MAI sparire. Per questo l'inbound fa una
    // UNIONE per id: aggiunge i messaggi remoti mancanti in locale e non
    // cancella mai i messaggi locali. Niente "Last-Writer-Wins" a livello di
    // messaggi (era fragile sui timestamp e poteva azzerare lo storico).
    // I campi di summary/compattazione restano in LWW.

    func applyAIChatInbound(
        changes: [AIConversationRemoteChange],
        modelContext: ModelContext
    ) {
        guard !changes.isEmpty else { return }
        KBLog.sync.kbDebug("[aiChat][inbound] applying changes=\(changes.count)")

        do {
            let locals = try modelContext.fetch(FetchDescriptor<KBAIConversation>())
            var localByKey: [String: KBAIConversation] = [:]
            for c in locals {
                localByKey[Self.aiKey(visitId: c.visitId, providerRaw: c.providerRaw)] = c
            }

            // Traccia se è stato applicato un cambiamento reale: gli echo delle
            // nostre stesse scritture NON devono notificare la UI, altrimenti
            // ricaricano i messaggi mentre l'AI sta rispondendo.
            var didApplyChange = false

            for change in changes {
                switch change {

                case .upsert(let dto):
                    let key = Self.aiKey(visitId: dto.visitId, providerRaw: dto.providerRaw)

                    // NOTA: non gestiamo isDeleted come cancellazione distruttiva
                    // (per non perdere storico). Un documento "svuotato" su un
                    // device non azzera gli altri.

                    if let existing = localByKey[key] {
                        let added = mergeMessages(dto: dto, into: existing, modelContext: modelContext)
                        // Summary/compattazione: LWW solo se il remoto è più recente.
                        if dto.updatedAt > existing.updatedAt {
                            existing.summary = dto.summary
                            existing.summaryUpdatedAt = dto.summaryUpdatedAt
                            existing.summarizedMessageCount = dto.summarizedMessageCount
                            existing.ownerUserId = dto.ownerUserId
                            existing.updatedAt = dto.updatedAt
                        }
                        if added > 0 { didApplyChange = true }
                        KBLog.sync.kbDebug("[aiChat][inbound] MERGED key=\(key) added=\(added)")
                    } else {
                        let convo = KBAIConversation(
                            id: dto.id,
                            familyId: dto.familyId,
                            childId: dto.childId,
                            visitId: dto.visitId,
                            provider: AIProvider(rawValue: dto.providerRaw) ?? .claude,
                            ownerUserId: dto.ownerUserId,
                            createdAt: dto.createdAt,
                            updatedAt: dto.updatedAt,
                            summary: dto.summary,
                            summaryUpdatedAt: dto.summaryUpdatedAt,
                            summarizedMessageCount: dto.summarizedMessageCount
                        )
                        modelContext.insert(convo)
                        _ = mergeMessages(dto: dto, into: convo, modelContext: modelContext)
                        localByKey[key] = convo
                        if !dto.messages.isEmpty { didApplyChange = true }
                        KBLog.sync.kbDebug("[aiChat][inbound] CREATED key=\(key) msgs=\(dto.messages.count)")
                    }

                case .remove:
                    // Niente cancellazione distruttiva dello storico.
                    break
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[aiChat][inbound] SAVE OK didApplyChange=\(didApplyChange)")
            if didApplyChange {
                Self._aiChatChanged.send(())
            }
        } catch {
            KBLog.sync.kbError("[aiChat][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }

    /// Unione per id: aggiunge i messaggi remoti mancanti, senza cancellare i
    /// messaggi locali. Restituisce quanti messaggi sono stati aggiunti.
    @discardableResult
    private func mergeMessages(
        dto: AIConversationDTO,
        into convo: KBAIConversation,
        modelContext: ModelContext
    ) -> Int {
        let existingIds = Set(convo.messages.map { $0.id })
        var added = 0
        for m in dto.messages.sorted(by: { $0.createdAt < $1.createdAt }) where !existingIds.contains(m.id) {
            let msg = KBAIMessage(
                id: m.id,
                role: AIMessageRole(rawValue: m.roleRaw) ?? .user,
                content: m.content,
                createdAt: m.createdAt
            )
            msg.conversation = convo
            modelContext.insert(msg)
            added += 1
        }
        return added
    }

    // MARK: - Helpers

    /// Chiave stabile di appaiamento delle conversazioni AI tra dispositivi.
    static func aiKey(visitId: String, providerRaw: String) -> String {
        "\(providerRaw)__\(visitId)"
    }
}
