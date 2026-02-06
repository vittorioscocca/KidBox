//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

enum KBSyncState: Int, Codable {
    case synced = 0
    case pendingUpsert = 1
    case pendingDelete = 2
    case error = 3
}
