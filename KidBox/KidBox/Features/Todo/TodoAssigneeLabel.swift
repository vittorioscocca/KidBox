//
//  TodoAssigneeLabel.swift
//  KidBox
//
//  Nome da mostrare sotto un to-do: il membro assegnato, oppure chi l'ha preso
//  da fuori dall'app rispondendo a una richiesta di famiglia
//  («Anna (fuori dall'app)»). In quel caso `assignedTo` è vuoto e il nome sta
//  in `assignedExternalName`.
//

import Foundation

extension KBTodoItem {
    /// - Parameter memberName: risolve un uid nel nome del membro.
    func assigneeDisplayName(memberName: (String) -> String?) -> String? {
        if let uid = assignedTo, !uid.isEmpty, let name = memberName(uid) {
            return name
        }
        guard (assignedTo ?? "").isEmpty,
              let external = assignedExternalName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !external.isEmpty
        else { return nil }
        return String(localized: "\(external) (fuori dall'app)")
    }
}
