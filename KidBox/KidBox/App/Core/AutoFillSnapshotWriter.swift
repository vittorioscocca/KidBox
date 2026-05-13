//
//  AutoFillSnapshotWriter.swift
//  KidBox
//
//  Ricostruisce lo snapshot cifrato da SwiftData (solo app principale).
//

import FirebaseAuth
import Foundation
import OSLog
import SwiftData

@MainActor
enum AutoFillSnapshotWriter {

    private static let debounceNanoseconds: UInt64 = 350_000_000
    private static var rebuildTask: Task<Void, Never>?

    static func scheduleRebuild(modelContext: ModelContext) {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await rebuild(modelContext: modelContext)
        }
    }

    static func rebuildNow(modelContext: ModelContext) async {
        rebuildTask?.cancel()
        await rebuild(modelContext: modelContext)
    }

    private static func rebuild(modelContext: ModelContext) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            tearDownAutoFillArtifacts()
            return
        }

        let familyId =
            UserDefaults(suiteName: KidBoxAutoFillPaths.appGroupId)?.string(forKey: "activeFamilyId")
            ?? UserDefaults.standard.string(forKey: "KidBox.activeFamilyId")

        guard let familyId, !familyId.isEmpty else {
            tearDownAutoFillArtifacts()
            return
        }

        guard let sym = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: uid) else {
            tearDownAutoFillArtifacts()
            return
        }

        do {
            try SharedFamilyKey.saveMirroredFamilyKey(sym)
        } catch {
            KBLog.security.error("AutoFill mirror key save failed: \(error.localizedDescription)")
        }

        let snapshot = buildSnapshot(familyId: familyId, currentUid: uid, modelContext: modelContext)

        do {
            let blob = try snapshot.encryptedBlob(using: sym)
            try AutoFillSnapshotFileStore.writeEncrypted(blob)
            UserDefaults(suiteName: KidBoxAutoFillPaths.appGroupId)?.set(snapshot.items.count, forKey: "kidbox.autofill.lastSnapshotCount")
            AutoFillSync.replaceQuickTypeCredentials(with: snapshot)
        } catch {
            KBLog.sync.kbError("[autofill] snapshot write failed: \(error.localizedDescription)")
        }

        let hosts = snapshot.items.compactMap(\.website)
        Task.detached(priority: .utility) {
            await Self.prefetchFavicons(hosts: hosts)
        }
    }

    private static func tearDownAutoFillArtifacts() {
        AutoFillSnapshotFileStore.deleteSnapshotFile()
        SharedFamilyKey.deleteMirroredFamilyKey()
        UserDefaults(suiteName: KidBoxAutoFillPaths.appGroupId)?.removeObject(forKey: "kidbox.autofill.lastSnapshotCount")
        AutoFillSync.clearQuickTypeCredentials()
    }

    /// Chiamare al logout esplicito (oltre a `tearDown` implicito quando non c’è sessione).
    static func clearAllAutoFillSharedArtifacts() {
        tearDownAutoFillArtifacts()
    }

    private static func buildSnapshot(familyId: String, currentUid: String, modelContext: ModelContext) -> AutoFillSnapshot {
        let desc = FetchDescriptor<PasswordEntry>(
            predicate: #Predicate { entry in
                entry.familyId == familyId && entry.deletedAt == nil
            }
        )
        let entries = (try? modelContext.fetch(desc)) ?? []
        var items: [AutoFillSnapshot.Item] = []
        items.reserveCapacity(entries.count)

        for entry in entries {
            guard entry.isVisible(to: currentUid) else { continue }

            do {
                let title = try entry.decryptTitle()
                let username = try entry.decryptUsername() ?? ""
                let password = try entry.decryptPassword()
                let websiteRaw = try entry.decryptWebsite()
                let host = AutoFillWebsiteHost.normalizedHost(from: websiteRaw)

                var otp: AutoFillOtpPayload?
                if let json = try entry.decryptOtpJson(),
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(AutoFillOtpPayload.self, from: data) {
                    otp = decoded
                }

                let item = AutoFillSnapshot.Item(
                    id: entry.id,
                    title: title,
                    username: username,
                    password: password,
                    website: host,
                    visibility: entry.visibility,
                    owner: entry.createdBy,
                    otp: otp
                )
                items.append(item)
            } catch {
                KBLog.sync.kbDebug("[autofill] skip entry id=\(entry.id) decrypt: \(error.localizedDescription)")
            }
        }

        return AutoFillSnapshot(version: 1, updatedAt: .now, items: items)
    }

    private static func prefetchFavicons(hosts: [String]) async {
        let session = URLSession.shared
        for host in Set(hosts) {
            guard let dest = KidBoxAutoFillPaths.faviconFileURL(forHost: host) else { continue }
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            var c = URLComponents(string: "https://www.google.com/s2/favicons")
            c?.queryItems = [
                URLQueryItem(name: "sz", value: "64"),
                URLQueryItem(name: "domain", value: host)
            ]
            guard let url = c?.url else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), data.count > 32, data.count < 200_000 else { continue }
                try data.write(to: dest, options: .atomic)
            } catch {
                continue
            }
        }
    }
}
