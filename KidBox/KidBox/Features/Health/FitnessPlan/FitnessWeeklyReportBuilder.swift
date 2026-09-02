//
//  FitnessWeeklyReportBuilder.swift
//  KidBox
//
//  Report di fine settimana (sezione 6 delle specifiche): il conteggio è
//  locale e non costa messaggi AI. L'AI entra in gioco solo se l'utente chiede
//  la proposta di adeguamento.
//

import Foundation

enum FitnessWeeklyReportBuilder {

    /// Report della settimana indicata.
    static func report(for weekIndex: Int, plan: FitnessPlanDocument) -> FitnessWeeklyReport? {
        guard let week = plan.weeks.first(where: { $0.index == weekIndex }) else { return nil }
        let trackable = week.sessions.filter { !$0.isRest }
        let done = trackable.filter { $0.status == .done }
        let skipped = trackable.filter { $0.status == .skipped }

        let minutes = done.reduce(0) { $0 + ($1.actualMinutes ?? $1.durationMinutes) }
        let kcal = done.reduce(0) { $0 + ($1.actualKcal ?? $1.targetKcal ?? 0) }

        let cal = Calendar.current
        let weekStart = cal.date(
            byAdding: .day,
            value: (weekIndex - 1) * 7,
            to: cal.startOfDay(for: plan.startDate)
        ) ?? plan.startDate

        return FitnessWeeklyReport(
            weekIndex: weekIndex,
            weekStart: weekStart,
            plannedSessions: trackable.count,
            completedSessions: done.count,
            skippedSessions: skipped.count,
            totalMinutes: minutes,
            totalKcal: kcal,
            substitutedSessions: done.filter(\.wasSubstituted).count,
            chronicallySkippedWeekdays: chronicallySkippedWeekdays(plan: plan, upTo: weekIndex)
        )
    }

    /// L'ultima settimana **conclusa** del piano, cioè quella il cui ultimo
    /// giorno è già passato. È il report che la dashboard propone il lunedì.
    static func lastCompletedWeekIndex(plan: FitnessPlanDocument, now: Date = Date()) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return plan.weeks
            .map(\.index)
            .filter { index in
                guard let weekEnd = cal.date(
                    byAdding: .day,
                    value: index * 7 - 1,
                    to: cal.startOfDay(for: plan.startDate)
                ) else { return false }
                return weekEnd < today
            }
            .max()
    }

    /// Giorni della settimana saltati almeno due volte: sono il segnale che
    /// l'AI usa per proporre di spostare quella seduta.
    private static func chronicallySkippedWeekdays(
        plan: FitnessPlanDocument,
        upTo weekIndex: Int
    ) -> [Int] {
        let cal = Calendar.current
        var counts: [Int: Int] = [:]
        for session in plan.allSessions
        where session.weekIndex <= weekIndex && !session.isRest {
            guard session.status == .skipped || session.status == .moved else { continue }
            let weekday = cal.component(.weekday, from: session.originalDate ?? session.date)
            counts[weekday, default: 0] += 1
        }
        return counts.filter { $0.value >= 2 }.keys.sorted()
    }
}
