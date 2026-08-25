//
//  TodoListExposure.swift
//  KidBox
//
//  Regola: una lista con solo To-Do non visibili agli altri membri non compare nella Home altrui.
//

import Foundation

enum TodoListExposure {
    /// Decide se un membro può vedere la riga di una lista.
    ///
    /// Serve almeno un To-Do attivo visibile a `currentUid`: una lista con soli
    /// To-Do privati non deve comparire sul dispositivo degli altri.
    ///
    /// **Liste vuote**: le vede solo chi le ha create. Nasconderle a tutti
    /// sarebbe stato scorretto — chi crea una lista se la vedrebbe sparire prima
    /// di poterci mettere dentro qualcosa — mentre mostrarle a tutti rivelava
    /// l'esistenza di liste che non contengono nulla di condiviso.
    ///
    /// **Liste senza autore**: quelle create prima dell'introduzione di
    /// `createdBy` restano visibili a tutti, altrimenti la regola nuova le
    /// farebbe sparire a chiunque, comprese quelle in uso da tempo.
    static func memberCanSeeListRow(
        listId: String,
        todos: [KBTodoItem],
        currentUid: String?,
        listCreatedBy: String? = nil
    ) -> Bool {
        guard let uid = currentUid, !uid.isEmpty else { return false }
        let activeInList = todos.filter { $0.listId == listId && !$0.isDeleted }
        if activeInList.isEmpty {
            guard let owner = listCreatedBy, !owner.isEmpty else { return true }
            return owner == uid
        }
        return activeInList.contains { $0.isVisible(to: uid) }
    }
}
