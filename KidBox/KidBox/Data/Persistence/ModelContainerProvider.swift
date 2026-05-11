//
//  ModelContainerProvider.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Creates and configures the SwiftData `ModelContainer` for KidBox.
///
/// KidBox is local-first:
/// - SwiftData provides the on-device persistence layer.
/// - Remote sync (Firestore/Storage) is handled separately by the sync layer.
///
/// Use cases:
/// - App runtime (persistent store on disk)
/// - Previews/tests (optional in-memory store)
enum ModelContainerProvider {
    
    /// `true` if this launch recreated the on-disk store by quarantining a corrupted/migration-blocking file.
    /// Used to trigger a Firestore bootstrap so existing users recover without reinstalling the app.
    private(set) static var didQuarantineCorruptedStoreThisLaunch = false
    
    private static let appGroupIdentifier = "group.it.vittorioscocca.kidbox"
    
    /// Apple store error often seen when lightweight migration cannot satisfy mandatory destination attributes (`NSCocoaErrorDomain` 134110).
    private static func isRecoverableMigrationOrLoadFailure(_ error: Error) -> Bool {
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 8 {
            depth += 1
            let ns = err as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == 134110 { return true }
            let msg = ns.localizedDescription.lowercased()
            if msg.contains("mandatory destination attribute")
                || (msg.contains("migration") && msg.contains("attribute")) {
                return true
            }
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }
    
    /// Moves the primary SQLite store and `-wal`/`-shm` siblings aside so SwiftData can create a fresh file.
    private static func quarantinePersistentStoreArtifacts(at storeURL: URL) {
        let fm = FileManager.default
        let parent = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        
        func moveAside(_ url: URL) {
            guard fm.fileExists(atPath: url.path) else { return }
            var destName = url.lastPathComponent + ".bak.\(stamp)"
            var destURL = parent.appendingPathComponent(destName)
            var attempt = 0
            while fm.fileExists(atPath: destURL.path) && attempt < 50 {
                attempt += 1
                destName = url.lastPathComponent + ".bak.\(stamp).\(attempt)"
                destURL = parent.appendingPathComponent(destName)
            }
            do {
                try fm.moveItem(at: url, to: destURL)
                KBLog.persistence.kbInfo("Quarantined corrupted store artifact: \(url.lastPathComponent)")
            } catch {
                KBLog.persistence.kbError(
                    "Quarantine move failed \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        
        moveAside(storeURL)
        moveAside(parent.appendingPathComponent("\(base)-wal"))
        moveAside(parent.appendingPathComponent("\(base)-shm"))
    }
    
    private static func appGroupPersistentStoreURL() -> URL? {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        if !FileManager.default.fileExists(atPath: support.path) {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        return support.appendingPathComponent("default.store")
    }
    
    /// Builds a `ModelContainer` containing all KidBox SwiftData models.
    ///
    /// - Parameter inMemory: Use `true` for previews/tests to avoid writing to disk.
    /// - Returns: Configured `ModelContainer`.
    ///
    /// - Important:
    ///   This must succeed for the app to run. On migration/load failures tied to incompatible
    ///   persisted schema, corrupted files are **quarantined once** and the container is retried so
    ///   users need not reinstall. If retry still fails, the app terminates with `fatalError`.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        didQuarantineCorruptedStoreThisLaunch = false
        KBLog.persistence.kbInfo("Creating ModelContainer inMemory=\(inMemory)")
        
        // Schema includes all persisted models used by the app.
        let schema = Schema([
            KBFamily.self,
            KBFamilyMember.self,
            KBChild.self,
            KBRoutine.self,
            KBRoutineCheck.self,
            KBEvent.self,
            KBTodoItem.self,
            KBTodoList.self,
            KBCustodySchedule.self,
            KBUserProfile.self,
            KBDocument.self,
            KBDocumentCategory.self,
            KBSyncOp.self,
            KBChatMessage.self,
            KBGroceryItem.self,
            KBNote.self,
            KBTreatment.self,
            KBMedicalVisit.self,
            KBPediatricProfile.self,
            KBVaccine.self,
            KBDoseLog.self,
            KBAIConversation.self,
            KBAIMessage.self,
            KBCustomDrug.self,
            KBMedicalExam.self,
            KBCalendarEvent.self,
            KBFamilyPhoto.self,
            KBPhotoAlbum.self,
            KBExpenseCategory.self,
            KBExpense.self,
            KBWalletTicket.self
        ])
        
        let configuration: ModelConfiguration = {
            if inMemory {
                return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: .automatic
            )
        }()
        
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            KBLog.persistence.kbInfo("ModelContainer created successfully")
            return container
        } catch {
            KBLog.persistence.kbError("ModelContainer creation failed: \(error.localizedDescription)")
            guard !inMemory, isRecoverableMigrationOrLoadFailure(error) else {
                fatalError("Could not create ModelContainer: \(error)")
            }
            let diskURL = appGroupPersistentStoreURL()
            KBLog.persistence.kbInfo(
                "ModelContainer retry path: quarantining on-disk SwiftData store and recreating container"
            )
            if let diskURL {
                quarantinePersistentStoreArtifacts(at: diskURL)
            }
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                didQuarantineCorruptedStoreThisLaunch = true
                KBLog.persistence.kbInfo("ModelContainer created successfully after store quarantine")
                return container
            } catch {
                KBLog.persistence.kbError("ModelContainer creation failed again: \(error.localizedDescription)")
                fatalError("Could not create ModelContainer after store recovery: \(error)")
            }
        }
    }
}
