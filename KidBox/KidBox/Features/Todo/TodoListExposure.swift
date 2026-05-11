//
//  TodoListExposure.swift
//  KidBox
//
//  Regola: una lista con solo To-Do non visibili agli altri membri non compare nella Home altrui.
//

import Foundation

enum TodoListExposure {
    /// Lista senza To-Do attivi: visibile a tutti. Altrimenti serve almeno un To-Do visibile a `currentUid`.
    static func memberCanSeeListRow(listId: String, todos: [KBTodoItem], currentUid: String?) -> Bool {
        guard let uid = currentUid, !uid.isEmpty else { return false }
        let activeInList = todos.filter { $0.listId == listId && !$0.isDeleted }
        if activeInList.isEmpty { return true }
        return activeInList.contains { $0.isVisible(to: uid) }
    }
}
