//
//  LocalDataWiper.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftData
import OSLog

enum LocalDataWiper {
    
    /// Deletes ALL local SwiftData entities (MVP).
    @MainActor
    static func wipeAll(context: ModelContext) throws {
        // Nota: ordine importante (prima child collections, poi family)
        try deleteAll(KBEvent.self, context: context)
        try deleteAll(KBTodoItem.self, context: context)
        try deleteAll(KBRoutine.self, context: context)
        try deleteAll(KBChild.self, context: context)
        try deleteAll(KBFamily.self, context: context)
        try deleteAll(KBUserProfile.self, context: context)
        
        try context.save()
        KBLog.persistence.info("Local SwiftData wiped")
    }
    
    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        items.forEach { context.delete($0) }
    }
}
