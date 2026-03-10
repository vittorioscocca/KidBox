//
//  HealthContextBuilder.swift
//  KidBox
//
//  Builds the AI system prompt for the PediatricHomeView health overview chat.
//  Works for both KBChild and KBFamilyMember — callers pass subjectName + subjectId.
//

import Foundation

enum HealthContextBuilder {
    
    // MARK: - Main entry point
    
    static func buildSystemPrompt(
        subjectName: String,
        subjectId: String,
        exams: [KBMedicalExam],
        visits: [KBMedicalVisit],
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        documentsByExamId: [String: [KBDocument]] = [:],
        documentsByVisitId: [String: [KBDocument]] = [:]
    ) -> String {
        
        KBLog.ai.kbInfo("""
        HealthContextBuilder start \
        subjectId=\(subjectId) \
        exams=\(exams.count) \
        visits=\(visits.count) \
        treatments=\(treatments.count) \
        vaccines=\(vaccines.count)
        """)
        
        var lines: [String] = []
        
        // ── Ruolo e regole ───────────────────────────────────────────────────
        lines.append("""
        Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.
        Il tuo ruolo è offrire una visione d'insieme chiara e comprensibile della salute della persona.
        
        REGOLE IMPORTANTI:
        - Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente, dopo aver dato il to parere,  di consultare il proprio medico.
        - Usa un linguaggio semplice, adatto a un genitore non esperto.
        - Puoi aiutare a capire cure in corso, vaccini, visite recenti, esami in attesa e referti allegati.
        - Se nei documenti ci sono testi estratti, usali per contestualizzare meglio.
        - Se un testo estratto sembra incompleto o ambiguo, dillo esplicitamente.
        - Rispondi sempre in italiano.
        """)
        
        // ── Profilo persona ──────────────────────────────────────────────────
        lines.append("\n--- PROFILO ---")
        lines.append("Nome: \(subjectName)")
        
        // ── Riepilogo veloce ─────────────────────────────────────────────────
        lines.append("\n--- RIEPILOGO SALUTE ---")
        lines.append("Cure attive: \(treatments.count)")
        lines.append("Vaccini registrati: \(vaccines.count)")
        lines.append("Visite registrate: \(visits.count)")
        lines.append("Esami totali: \(exams.count)")
        
        let pendingExams = exams.filter { $0.status == .pending || $0.status == .booked }
        if !pendingExams.isEmpty {
            lines.append("Esami in attesa / prenotati: \(pendingExams.count)")
        }
        let urgentExams = exams.filter { $0.isUrgent && ($0.status == .pending || $0.status == .booked) }
        if !urgentExams.isEmpty {
            lines.append("Esami urgenti: \(urgentExams.count)")
        }
        
        // ── Cure attive ──────────────────────────────────────────────────────
        appendTreatments(treatments, to: &lines)
        
        // ── Vaccini ──────────────────────────────────────────────────────────
        appendVaccines(vaccines, to: &lines)
        
        // ── Visite (più recenti prima) ───────────────────────────────────────
        let sortedVisits = visits.sorted { $0.date > $1.date }
        appendVisits(sortedVisits, documentsByVisitId: documentsByVisitId, to: &lines)
        
        // ── Esami ────────────────────────────────────────────────────────────
        let sortedExams = exams.sorted {
            ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
        }
        appendExams(sortedExams, documentsByExamId: documentsByExamId, to: &lines)
        
        // ── Chiusura ─────────────────────────────────────────────────────────
        lines.append("\n--- FINE CONTESTO SALUTE ---")
        lines.append("Rispondi alle domande usando le informazioni sopra.")
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("HealthContextBuilder end chars=\(prompt.count)")
        return prompt
    }
    
    // MARK: - Treatments
    
    private static func appendTreatments(_ treatments: [KBTreatment], to lines: inout [String]) {
        guard !treatments.isEmpty else { return }
        
        lines.append("\n--- CURE ATTIVE (\(treatments.count)) ---")
        for t in treatments {
            var line = "• \(t.drugName)"
            line += " — \(t.dosageValue, default: "%.0f") \(t.dosageUnit)"
            line += ", \(t.dailyFrequency)x/giorno"
            if t.isLongTerm {
                line += ", lungo termine"
            } else {
                line += ", \(t.durationDays) giorni"
                if let end = t.endDate { line += " (fine: \(formatDate(end)))" }
            }
            if let notes = t.notes, !notes.isEmpty { line += " — \(notes)" }
            lines.append(line)
        }
        KBLog.ai.kbDebug("HealthContextBuilder treatments appended count=\(treatments.count)")
    }
    
    // MARK: - Vaccines
    
    private static func appendVaccines(_ vaccines: [KBVaccine], to lines: inout [String]) {
        guard !vaccines.isEmpty else { return }
        
        let sorted = vaccines.sorted { (a: KBVaccine, b: KBVaccine) in
            let dateA = a.administeredDate ?? a.scheduledDate ?? a.createdAt
            let dateB = b.administeredDate ?? b.scheduledDate ?? b.createdAt
            return dateA > dateB
        }
        
        lines.append("\n--- VACCINI (\(sorted.count)) ---")
        
        for v in sorted {
            let displayName = v.commercialName.flatMap { $0.isEmpty ? nil : $0 } ?? v.vaccineType.displayName
            
            var datePart = ""
            if let administered = v.administeredDate {
                datePart = "somministrato il \(formatDate(administered))"
            } else if let scheduled = v.scheduledDate {
                datePart = "programmato per \(formatDate(scheduled))"
            }
            
            var line = "• \(displayName)"
            if !datePart.isEmpty { line += " — \(datePart)" }
            if v.totalDoses > 1  { line += " (dose \(v.doseNumber)/\(v.totalDoses))" }
            line += " [\(v.status.rawValue)]"
            if let lot   = v.lotNumber,      !lot.isEmpty   { line += " — Lotto: \(lot)" }
            if let by    = v.administeredBy, !by.isEmpty    { line += " — \(by)" }
            if let notes = v.notes,          !notes.isEmpty { line += " — \(notes)" }
            lines.append(line)
        }
        
        KBLog.ai.kbDebug("HealthContextBuilder vaccines appended count=\(sorted.count)")
    }
    
    // MARK: - Visits
    
    private static func appendVisits(
        _ visits: [KBMedicalVisit],
        documentsByVisitId: [String: [KBDocument]],
        to lines: inout [String]
    ) {
        guard !visits.isEmpty else { return }
        
        lines.append("\n--- VISITE MEDICHE (\(visits.count)) ---")
        
        for (index, visit) in visits.enumerated() {
            lines.append("")
            lines.append("## VISITA \(index + 1) — \(formatDate(visit.date))")
            
            if !visit.reason.isEmpty { lines.append("Motivo: \(visit.reason)") }
            
            if let doctor = visit.doctorName, !doctor.isEmpty {
                var dl = "Medico: \(doctor)"
                if let spec = visit.doctorSpecialization { dl += " (\(spec.rawValue))" }
                lines.append(dl)
            }
            
            if let diagnosis = visit.diagnosis, !diagnosis.isEmpty {
                lines.append("Diagnosi: \(diagnosis)")
            }
            
            if let recommendations = visit.recommendations, !recommendations.isEmpty {
                lines.append("Raccomandazioni: \(recommendations)")
            }
            
            if !visit.asNeededDrugs.isEmpty {
                let drugList = visit.asNeededDrugs
                    .map { "\($0.drugName) \($0.dosageValue, default: "%.0f") \($0.dosageUnit)" }
                    .joined(separator: ", ")
                lines.append("Farmaci al bisogno: \(drugList)")
            }
            
            if !visit.therapyTypes.isEmpty {
                lines.append("Terapie: \(visit.therapyTypes.map(\.rawValue).joined(separator: ", "))")
            }
            
            if !visit.prescribedExams.isEmpty {
                let examList = visit.prescribedExams
                    .map { "\($0.name)\($0.isUrgent ? " [URGENTE]" : "")" }
                    .joined(separator: ", ")
                lines.append("Esami prescritti: \(examList)")
            }
            
            if let notes = visit.notes, !notes.isEmpty { lines.append("Note: \(notes)") }
            
            if let nextDate = visit.nextVisitDate {
                var nl = "Prossima visita: \(formatDate(nextDate))"
                if let reason = visit.nextVisitReason, !reason.isEmpty { nl += " — \(reason)" }
                lines.append(nl)
            }
            
            let docs = (documentsByVisitId[visit.id] ?? [])
                .filter { $0.extractionStatus == .completed && $0.hasExtractedText }
            for doc in docs {
                let clean = sanitizeExtractedText(doc.extractedText ?? "")
                guard !clean.isEmpty else { continue }
                lines.append("Referto allegato (\(doc.title)):")
                lines.append(clean)
            }
        }
        KBLog.ai.kbDebug("HealthContextBuilder visits appended count=\(visits.count)")
    }
    
    // MARK: - Exams
    
    private static func appendExams(
        _ exams: [KBMedicalExam],
        documentsByExamId: [String: [KBDocument]],
        to lines: inout [String]
    ) {
        guard !exams.isEmpty else { return }
        
        lines.append("\n--- ESAMI (\(exams.count)) ---")
        
        for exam in exams {
            var line = "• \(exam.name) [\(exam.status.rawValue)]"
            if exam.isUrgent { line += " [URGENTE]" }
            if let deadline = exam.deadline {
                let overdue = deadline < Date() && (exam.status == .pending || exam.status == .booked)
                line += " — scadenza: \(formatDate(deadline))\(overdue ? " ⚠️ SCADUTA" : "")"
            }
            if let result = exam.resultText, !result.isEmpty {
                line += " — Risultato: \(result)"
            }
            lines.append(line)
            
            let docs = (documentsByExamId[exam.id] ?? [])
                .filter { $0.extractionStatus == .completed && $0.hasExtractedText }
            for doc in docs {
                let clean = sanitizeExtractedText(doc.extractedText ?? "")
                guard !clean.isEmpty else { continue }
                lines.append("  Referto (\(doc.title)):")
                lines.append("  \(clean)")
            }
        }
        KBLog.ai.kbDebug("HealthContextBuilder exams appended count=\(exams.count)")
    }
    
    // MARK: - Private helpers
    
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    private static func sanitizeExtractedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
