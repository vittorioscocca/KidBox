//
//  KBHealthLinkStore.swift
//  KidBox
//

import Foundation

/// Persistenza locale dell'ultimo abbinamento Salute per profilo (childId).
enum KBHealthLinkStore {

    private static let prefix = "kidbox.health.link."

    static func load(childId: String) -> KBHealthImportSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(childId)) else { return nil }
        return try? JSONDecoder().decode(KBHealthImportSnapshot.self, from: data)
    }

    static func save(_ snapshot: KBHealthImportSnapshot, childId: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key(childId))
    }

    static func clear(childId: String) {
        UserDefaults.standard.removeObject(forKey: key(childId))
    }

    private static func key(_ childId: String) -> String { prefix + childId }
}
