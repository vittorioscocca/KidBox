import Foundation
import SwiftData
import CryptoKit
import CommonCrypto

enum MergeStrategy: String, CaseIterable, Identifiable {
    case skipDuplicates
    case overwriteByTitleUsername
    case keepBoth
    var id: String { rawValue }
}

struct ImportConflict: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let username: String
}

struct ImportLineError: Identifiable, Hashable {
    let id = UUID()
    let row: Int
    let message: String
}

struct ImportPreview {
    let totalCount: Int
    let conflicts: [ImportConflict]
    let groupsToCreate: [String]
    let rowErrors: [ImportLineError]
    let skippedOnlyCreatorFromOtherUsers: Int
    let legacyAmbiguousRecordIndices: [Int]
    fileprivate let records: [ParsedPasswordRecord]
}

fileprivate struct ParsedPasswordRecord {
    let title: String
    let username: String
    let password: String
    let website: String
    let groupName: String
    let visibility: String
    let notes: String
    let createdBy: String
    let isFavorite: Bool
}

@MainActor
struct PasswordsTxtImporter {
    enum ImportError: Error {
        case invalidFile
        case emptyFile
        case missingCurrentUser
        case wrongPassphrase
        case keyDerivationFailed
    }

    let familyId: String
    let modelContext: ModelContext
    let currentUid: String?

    func parse(url: URL, passphrase: String?) async throws -> ImportPreview {
        guard let currentUid, !currentUid.isEmpty else { throw ImportError.missingCurrentUser }
        var raw = try decodeText(from: url)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ImportError.emptyFile }

        if raw.hasPrefix("# KidBox Password Export v1 (encrypted)\n") {
            let payload = raw.replacingOccurrences(of: "# KidBox Password Export v1 (encrypted)\n", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let passphrase, !passphrase.isEmpty else { throw ImportError.wrongPassphrase }
            raw = try decrypt(payloadBase64: payload, passphrase: passphrase)
        }

        let existing = try loadExistingEntries(currentUid: currentUid)
        let existingKeys = Set(existing.map { normalizedKey(title: $0.0, username: $0.1) })

        let parsed = parseRecords(from: raw, currentUid: currentUid)
        let conflicts = parsed.records
            .filter { existingKeys.contains(normalizedKey(title: $0.title, username: $0.username)) }
            .map { ImportConflict(title: $0.title, username: $0.username) }

        let knownGroups = Set(try loadGroupNames(currentUid: currentUid).map(normalizeGroupName))
        let groupsToCreate = Array(Set(parsed.records.map(\.groupName).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .filter { !knownGroups.contains(normalizeGroupName($0)) }
            .sorted()

        return ImportPreview(
            totalCount: parsed.records.count,
            conflicts: conflicts,
            groupsToCreate: groupsToCreate,
            rowErrors: parsed.errors,
            skippedOnlyCreatorFromOtherUsers: parsed.skippedOnlyCreatorFromOtherUsers,
            legacyAmbiguousRecordIndices: parsed.legacyAmbiguousRecordIndices,
            records: parsed.records
        )
    }

    func commit(preview: ImportPreview, strategy: MergeStrategy) async throws {
        guard let currentUid, !currentUid.isEmpty else { throw ImportError.missingCurrentUser }

        var groupsByName = try loadGroupsByName(currentUid: currentUid)
        for groupName in preview.groupsToCreate {
            let norm = normalizeGroupName(groupName)
            guard groupsByName[norm] == nil else { continue }
            let cipher = try PasswordCypher.encrypt(groupName, familyId: familyId, visibility: KBVisibilityScope.family, createdBy: currentUid)
            let group = PasswordGroup(
                familyId: familyId,
                nameCipher: cipher,
                icon: "folder.fill",
                color: "#7C6FDE",
                visibility: KBVisibilityScope.family,
                visibilityMemberIds: [],
                createdBy: currentUid,
                isSystem: false
            )
            group.syncState = .pendingUpsert
            modelContext.insert(group)
            PasswordsRepository.enqueuePasswordGroupUpsert(groupId: group.id, familyId: familyId, modelContext: modelContext)
            groupsByName[norm] = group
        }

        let existingEntries = try fetchEntries(currentUid: currentUid)
        var indexByKey: [String: PasswordEntry] = [:]
        for entry in existingEntries {
            let title = (try? entry.decryptTitle()) ?? ""
            let username = (try? entry.decryptUsername()) ?? ""
            indexByKey[normalizedKey(title: title, username: username)] = entry
        }

        for record in preview.records {
            let key = normalizedKey(title: record.title, username: record.username)
            let existing = indexByKey[key]
            let group = groupsByName[normalizeGroupName(record.groupName)] ?? PasswordGroupsService.resolveUnassignedGroup(familyId: familyId, modelContext: modelContext)
            let visibility = PasswordEntry.normalizedPasswordVisibility(record.visibility)
            let createdBy = visibility == KBVisibilityScope.onlyCreator ? currentUid : currentUid

            switch (existing, strategy) {
            case (.some, .skipDuplicates):
                continue
            case (.some(let entry), .overwriteByTitleUsername):
                try fill(entry: entry, with: record, currentUid: currentUid, groupId: group?.id, visibility: visibility, createdBy: createdBy)
                PasswordsRepository.enqueuePasswordEntryUpsert(entryId: entry.id, familyId: familyId, modelContext: modelContext)
            default:
                let entry = try makeEntry(from: record, currentUid: currentUid, groupId: group?.id, visibility: visibility, createdBy: createdBy)
                modelContext.insert(entry)
                PasswordsRepository.enqueuePasswordEntryUpsert(entryId: entry.id, familyId: familyId, modelContext: modelContext)
                indexByKey[key] = entry
            }
        }

        try modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    private func fill(entry: PasswordEntry, with record: ParsedPasswordRecord, currentUid: String, groupId: String?, visibility: String, createdBy: String) throws {
        entry.groupId = groupId
        entry.visibility = visibility
        entry.createdBy = createdBy
        entry.titleCipher = try PasswordCypher.encrypt(record.title, familyId: familyId, visibility: visibility, createdBy: createdBy)
        entry.passwordCipher = try PasswordCypher.encrypt(record.password, familyId: familyId, visibility: visibility, createdBy: createdBy)
        entry.usernameCipher = record.username.isEmpty ? nil : try PasswordCypher.encrypt(record.username, familyId: familyId, visibility: visibility, createdBy: createdBy)
        entry.websiteCipher = record.website.isEmpty ? nil : try PasswordCypher.encrypt(record.website, familyId: familyId, visibility: visibility, createdBy: createdBy)
        entry.notesCipher = record.notes.isEmpty ? nil : try PasswordCypher.encrypt(record.notes, familyId: familyId, visibility: visibility, createdBy: createdBy)
        entry.isFavorite = record.isFavorite
        entry.updatedAt = .now
        entry.passwordUpdatedAt = .now
        entry.syncState = .pendingUpsert
        entry.lastSyncError = nil
    }

    private func makeEntry(from record: ParsedPasswordRecord, currentUid: String, groupId: String?, visibility: String, createdBy: String) throws -> PasswordEntry {
        let entry = PasswordEntry(
            familyId: familyId,
            createdBy: createdBy,
            visibility: visibility,
            visibilityMemberIds: [],
            groupId: groupId,
            titleCipher: try PasswordCypher.encrypt(record.title, familyId: familyId, visibility: visibility, createdBy: createdBy),
            usernameCipher: record.username.isEmpty ? nil : try PasswordCypher.encrypt(record.username, familyId: familyId, visibility: visibility, createdBy: createdBy),
            passwordCipher: try PasswordCypher.encrypt(record.password, familyId: familyId, visibility: visibility, createdBy: createdBy),
            websiteCipher: record.website.isEmpty ? nil : try PasswordCypher.encrypt(record.website, familyId: familyId, visibility: visibility, createdBy: createdBy),
            notesCipher: record.notes.isEmpty ? nil : try PasswordCypher.encrypt(record.notes, familyId: familyId, visibility: visibility, createdBy: createdBy),
            isFavorite: record.isFavorite
        )
        entry.syncState = .pendingUpsert
        return entry
    }

    private func parseRecords(from text: String, currentUid: String) -> (records: [ParsedPasswordRecord], errors: [ImportLineError], skippedOnlyCreatorFromOtherUsers: Int, legacyAmbiguousRecordIndices: [Int]) {
        var errors: [ImportLineError] = []
        var records: [ParsedPasswordRecord] = []
        var skippedOthersPrivate = 0

        let legacy = parseLegacyRecords(from: text)
        if !legacy.records.isEmpty {
            return (legacy.records, [], 0, legacy.ambiguousRecordIndices)
        }

        let lines = text.components(separatedBy: .newlines)
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                if !current.isEmpty { blocks.append(current); current = [] }
                continue
            }
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        for (index, block) in blocks.enumerated() {
            var map: [String: String] = [:]
            for raw in block {
                guard let sep = raw.firstIndex(of: ":") else { continue }
                let key = raw[..<sep].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = raw[raw.index(after: sep)...].trimmingCharacters(in: .whitespacesAndNewlines)
                map[key] = unescape(value)
            }

            let title = (map["Title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let password = map["Password"] ?? ""
            if title.isEmpty {
                errors.append(.init(row: index + 1, message: "Blocco senza Title"))
                continue
            }
            if password.isEmpty {
                errors.append(.init(row: index + 1, message: "Blocco senza Password"))
                continue
            }

            let rawVisibility = (map["Visibility"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let visibility = rawVisibility.isEmpty
                ? KBVisibilityScope.onlyCreator
                : PasswordEntry.normalizedPasswordVisibility(rawVisibility)
            let createdBy = (map["CreatedBy"] ?? currentUid).trimmingCharacters(in: .whitespacesAndNewlines)
            if visibility == KBVisibilityScope.onlyCreator, createdBy != currentUid {
                skippedOthersPrivate += 1
                continue
            }

            let favRaw = (map["Favorite"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isFavorite = ["true", "1", "yes", "si"].contains(favRaw)

            records.append(
                ParsedPasswordRecord(
                    title: title,
                    username: map["Username"] ?? "",
                    password: password,
                    website: map["WebSite"] ?? "",
                    groupName: map["Group"] ?? "",
                    visibility: visibility,
                    notes: map["Note"] ?? "",
                    createdBy: createdBy,
                    isFavorite: isFavorite
                )
            )
        }
        return (records, errors, skippedOthersPrivate, [])
    }

    private func parseLegacyRecords(from text: String) -> (records: [ParsedPasswordRecord], ambiguousRecordIndices: [Int]) {
        let pattern = #"Account:\s(.*?)\sGroup:\s(.*?)\sWebSite:\s(.*?)\sUsername:\s(.*?)\sPassword:\s(.*?)\sNote:\s(.*?)(?=Account:\s|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ([], [])
        }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return ([], []) }

        let validStarts = Set(matches.map(\.range.location))
        var ambiguousByRecord: Set<Int> = []
        let tokenRegex = try? NSRegularExpression(pattern: #"Account:\s"#)
        if let tokenRegex {
            let tokenMatches = tokenRegex.matches(in: text, options: [], range: fullRange)
            for token in tokenMatches where !validStarts.contains(token.range.location) {
                let ownerIndex = matches.lastIndex(where: { $0.range.location < token.range.location }) ?? 0
                ambiguousByRecord.insert(ownerIndex + 1)
            }
        }

        if let noteTokenRegex = try? NSRegularExpression(pattern: #"Account:\s"#) {
            for (idx, match) in matches.enumerated() {
                let noteRange = match.range(at: 6)
                if noteRange.location != NSNotFound,
                   noteTokenRegex.firstMatch(in: text, options: [], range: noteRange) != nil {
                    ambiguousByRecord.insert(idx + 1)
                }
            }
        }

        let out: [ParsedPasswordRecord] = matches.compactMap { match in
            guard match.numberOfRanges == 7 else { return nil }
            return ParsedPasswordRecord(
                title: ns.substring(with: match.range(at: 1)),
                username: ns.substring(with: match.range(at: 4)),
                password: ns.substring(with: match.range(at: 5)),
                website: ns.substring(with: match.range(at: 3)),
                groupName: ns.substring(with: match.range(at: 2)),
                visibility: KBVisibilityScope.onlyCreator,
                notes: ns.substring(with: match.range(at: 6)),
                createdBy: "",
                isFavorite: false
            )
        }
        return (out, ambiguousByRecord.sorted())
    }

    private func decodeText(from url: URL) throws -> String {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw ImportError.emptyFile }
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        guard let text = String(data: Data(body), encoding: .utf8) else { throw ImportError.invalidFile }
        return text
    }

    private func decrypt(payloadBase64: String, passphrase: String) throws -> String {
        guard let payload = Data(base64Encoded: payloadBase64), payload.count > 16 else { throw ImportError.invalidFile }
        let salt = payload.prefix(16)
        let combined = payload.dropFirst(16)
        let keyData = try deriveKey(passphrase: passphrase, salt: Data(salt))
        let key = SymmetricKey(data: keyData)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plain = try AES.GCM.open(box, using: key)
            guard let text = String(data: plain, encoding: .utf8) else { throw ImportError.invalidFile }
            return text
        } catch {
            throw ImportError.wrongPassphrase
        }
    }

    private func deriveKey(passphrase: String, salt: Data) throws -> Data {
        var out = Data(repeating: 0, count: 32)
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase, passphrase.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100_000,
                    outBytes.bindMemory(to: UInt8.self).baseAddress!, outCount
                )
            }
        }
        guard status == kCCSuccess else { throw ImportError.keyDerivationFailed }
        return out
    }

    private func loadExistingEntries(currentUid: String) throws -> [(String, String)] {
        try fetchEntries(currentUid: currentUid).map { ((try? $0.decryptTitle()) ?? "", (try? $0.decryptUsername()) ?? "") }
    }

    private func fetchEntries(currentUid: String) throws -> [PasswordEntry] {
        let desc = FetchDescriptor<PasswordEntry>(predicate: #Predicate { $0.familyId == familyId && $0.deletedAt == nil })
        return try modelContext.fetch(desc).filter { $0.isVisible(to: currentUid) }
    }

    private func loadGroupNames(currentUid: String) throws -> [String] {
        let desc = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.familyId == familyId && $0.deletedAt == nil })
        return try modelContext.fetch(desc).filter { $0.isVisible(to: currentUid) }.compactMap { try? $0.decryptName() }
    }

    private func loadGroupsByName(currentUid: String) throws -> [String: PasswordGroup] {
        let desc = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.familyId == familyId && $0.deletedAt == nil })
        var map: [String: PasswordGroup] = [:]
        for group in try modelContext.fetch(desc).filter({ $0.isVisible(to: currentUid) }) {
            if let name = try? group.decryptName() {
                map[normalizeGroupName(name)] = group
            }
        }
        return map
    }

    private func normalizedKey(title: String, username: String) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func normalizeGroupName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
