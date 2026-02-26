//
//  TodoHighlightStore.swift
//  KidBox
//
//  Created by vscocca on 26/02/26.
//

import Foundation
import Combine

@MainActor
final class TodoHighlightStore: ObservableObject {
    static let shared = TodoHighlightStore()
    private init() {}
    
    /// Todo da evidenziare appena la lista è pronta.
    @Published var todoIdToHighlight: String? = nil
    
    func set(_ id: String?) {
        todoIdToHighlight = id
    }
    
    func consumeIfMatches(_ id: String) {
        if todoIdToHighlight == id { todoIdToHighlight = nil }
    }
}
