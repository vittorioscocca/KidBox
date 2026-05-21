//
//  KBGeofence.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import Foundation
import SwiftData

/// Zona di arrivo/partenza monitorata con Core Location.
///
/// Quando un membro entra o esce dal raggio, l'app può notificare altri membri.
/// - `monitoredMemberIds` vuoto = la zona si applica a chiunque condivida la posizione.
/// - `notifyMembers` vuoto = avvisa tutta la famiglia (escluso chi ha generato l'evento).
@Model
final class KBGeofence {
    @Attribute(.unique) var id: String
    var familyId: String

    var name: String
    var emoji: String?

    var latitude: Double
    var longitude: Double
    /// Raggio in metri (default 200).
    var radius: Double

    var notifyOnArrive: Bool
    var notifyOnLeave: Bool
    /// UID destinatari notifica; vuoto = tutti i membri.
    var notifyMembers: [String]
    /// UID soggetti monitorati sul loro telefono; vuoto = tutti chi condividono la posizione.
    var monitoredMemberIds: [String]

    var isActive: Bool

    var createdBy: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        emoji: String? = nil,
        latitude: Double,
        longitude: Double,
        radius: Double = 200,
        notifyOnArrive: Bool = true,
        notifyOnLeave: Bool = false,
        notifyMembers: [String] = [],
        monitoredMemberIds: [String] = [],
        isActive: Bool = true,
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.emoji = emoji
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.notifyOnArrive = notifyOnArrive
        self.notifyOnLeave = notifyOnLeave
        self.notifyMembers = notifyMembers
        self.monitoredMemberIds = monitoredMemberIds
        self.isActive = isActive
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

extension KBGeofence: HasFamilyId {}
