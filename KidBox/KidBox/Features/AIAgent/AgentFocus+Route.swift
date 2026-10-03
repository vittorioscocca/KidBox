//
//  AgentFocus+Route.swift
//  KidBox
//
//  Dal 03/10/2026 l'assistente si apre dalla barra in basso, non più dai
//  pulsanti di Home e Salute. Il focus che quei pulsanti passavano (persona,
//  visita, esame) ora si ricava dalla schermata in cima alla pila: aprire
//  l'assistente da una visita lo centra su quella visita, come prima.
//

import Foundation
import SwiftData

extension Route {

    /// Le schermate su cui resta la barra: le due radici (pila vuota) e Salute
    /// con le sue sottosezioni, dove prima c'era il pulsante AI. Piano
    /// alimentare e Piano fitness no: hanno il loro AI e un'azione in basso.
    var showsRootTabBar: Bool {
        switch self {
        case .pediatricChildSelector, .pediatricHome, .pediatricMedicalRecord, .appleHealthApp,
             .pediatricVisits, .pediatricVisitDetail, .pediatricVaccines, .pediatricTreatments,
             .pediatricTreatmentDetail, .pediatricExams, .examDetail, .pediatricTimeline,
             .pediatricClinicalRecord:
            return true
        default:
            return false
        }
    }
}

extension AgentFocus {

    /// Il focus per la schermata in cima alla pila, o nil se non è di Salute.
    /// `childId` delle rotte è il soggetto: un figlio (`KBChild.id`) o un
    /// adulto (`KBFamilyMember.userId`), come in `PediatricHomeView`.
    @MainActor
    static func forRoute(_ route: Route?, context: ModelContext) -> AgentFocus? {
        guard let route else { return nil }
        switch route {
        case let .pediatricHome(_, childId),
             let .pediatricMedicalRecord(_, childId),
             let .appleHealthApp(_, childId),
             let .pediatricVaccines(_, childId),
             let .pediatricTreatments(_, childId),
             let .pediatricTreatmentDetail(_, childId, _),
             let .pediatricTimeline(_, childId),
             let .pediatricClinicalRecord(_, childId):
            return person(childId, context: context).map { AgentFocus(personId: childId, personName: $0, scope: .person) }
        case let .pediatricVisits(_, childId):
            return person(childId, context: context).map { AgentFocus(personId: childId, personName: $0, scope: .visits) }
        case let .pediatricVisitDetail(_, childId, visitId):
            guard let name = person(childId, context: context) else { return nil }
            let vid = visitId
            let visit = try? context.fetch(FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })).first
            let detail = visit.map {
                String(
                    format: NSLocalizedString("Visita del %@", comment: "Assistant focus label: visit date"),
                    $0.date.formatted(.dateTime.day().month(.abbreviated).year().locale(kbDeviceLocale()))
                )
            }
            return AgentFocus(personId: childId, personName: name, scope: .visit(id: visitId), detail: detail)
        case let .pediatricExams(_, childId):
            return person(childId, context: context).map { AgentFocus(personId: childId, personName: $0, scope: .exams) }
        case let .examDetail(_, childId, examId):
            guard let name = person(childId, context: context) else { return nil }
            let eid = examId
            let exam = try? context.fetch(FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })).first
            let detail = exam?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgentFocus(personId: childId, personName: name, scope: .exam(id: examId), detail: detail)
        default:
            return nil
        }
    }

    @MainActor
    private static func person(_ id: String, context: ModelContext) -> String? {
        guard !id.isEmpty else { return nil }
        let pid = id
        if let child = try? context.fetch(FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == pid })).first {
            return child.name
        }
        if let member = try? context.fetch(FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.userId == pid })).first,
           let name = member.displayName, !name.isEmpty {
            return name
        }
        return nil
    }
}
