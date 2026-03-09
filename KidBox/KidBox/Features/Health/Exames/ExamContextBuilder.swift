//
//  PediatricExamsAIChatViewModel.swift
//  KidBox
//

import Foundation

/// Builds the AI system prompt for exam-related chats.
/// Covers both a single exam and a list of exams (mirrors MedicalVisitContextBuilder).
enum ExamContextBuilder {
    
    // MARK: - Single exam
    
    static func buildSystemPrompt(
        exam: KBMedicalExam,
        subjectName: String,
        documents: [KBDocument] = []
    ) -> String {
        KBLog.ai.kbInfo("ExamContextBuilder single start examId=\(exam.id) documents=\(documents.count)")
        
        var lines: [String] = []
        
        lines.append("""
        Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.
        Il tuo ruolo è spiegare in modo chiaro e comprensibile le informazioni relative a un esame medico pediatrico.
        
        REGOLE IMPORTANTI:
        - Non fare diagnosi e non sostituirti al medico.
        - Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente di consultare il proprio medico.
        - Usa un linguaggio semplice, adatto a un genitore non esperto.
        - Puoi spiegare cos'è l'esame, come prepararsi, cosa significa il risultato e il contenuto dei referti allegati.
        - Se nel contesto sono presenti testi estratti da referti, usali per spiegare meglio il contenuto.
        - Se un testo estratto sembra incompleto o poco chiaro, dillo esplicitamente.
        - Rispondi sempre in italiano.
        """)
        
        lines.append("\n--- DATI ESAME ---")
        lines.append("Bambino/Persona: \(subjectName)")
        lines.append("Nome esame: \(exam.name)")
        lines.append("Stato: \(exam.status.rawValue)")
        
        if exam.isUrgent {
            lines.append("Urgente: sì")
        }
        
        if let deadline = exam.deadline {
            let isOverdue = deadline < Date() && (exam.status == .pending || exam.status == .booked)
            lines.append("Scadenza: \(formatDate(deadline))\(isOverdue ? " ⚠️ SCADUTA" : "")")
        }
        
        if let location = exam.location, !location.isEmpty {
            lines.append("Luogo: \(location)")
        }
        
        if let preparation = exam.preparation, !preparation.isEmpty {
            lines.append("\nPreparazione richiesta:\n\(preparation)")
        }
        
        if let notes = exam.notes, !notes.isEmpty {
            lines.append("\nNote:\n\(notes)")
        }
        
        if let resultText = exam.resultText, !resultText.isEmpty {
            lines.append("\nRisultato:\n\(resultText)")
        }
        
        if let resultDate = exam.resultDate {
            lines.append("Data risultato: \(formatDate(resultDate))")
        }
        
        appendDocuments(documents, to: &lines, context: "esame")
        
        lines.append("\n--- FINE DATI ESAME ---")
        lines.append("\nRispondi alle domande del genitore sull'esame usando le informazioni sopra.")
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("ExamContextBuilder single end examId=\(exam.id) chars=\(prompt.count)")
        return prompt
    }
    
    // MARK: - All exams
    
    static func buildSystemPrompt(
        exams: [KBMedicalExam],
        subjectName: String,
        documentsByExamId: [String: [KBDocument]] = [:]
    ) -> String {
        KBLog.ai.kbInfo("ExamContextBuilder all start exams=\(exams.count)")
        
        var lines: [String] = []
        
        lines.append("""
        Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.
        Il tuo ruolo è spiegare in modo chiaro e comprensibile l'insieme degli esami medici pediatrici del bambino.
        
        REGOLE IMPORTANTI:
        - Non fare diagnosi e non sostituirti al medico.
        - Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente di consultare il proprio medico.
        - Usa un linguaggio semplice, adatto a un genitore non esperto.
        - Puoi aiutare a capire quali esami sono in scadenza, urgenti, con risultato disponibile, e il contenuto dei referti.
        - Se nei documenti ci sono testi estratti, usali.
        - Se un testo estratto sembra incompleto o ambiguo, dillo chiaramente.
        - Rispondi sempre in italiano.
        """)
        
        lines.append("\n--- PROFILO ---")
        lines.append("Bambino/Persona: \(subjectName)")
        lines.append("Numero esami nel contesto: \(exams.count)")
        
        // Riepilogo rapido per stato
        let byStatus = Dictionary(grouping: exams, by: \.status)
        let statusSummary = KBExamStatus.allCases
            .compactMap { s -> String? in
                guard let count = byStatus[s]?.count, count > 0 else { return nil }
                return "\(s.rawValue): \(count)"
            }
            .joined(separator: ", ")
        if !statusSummary.isEmpty {
            lines.append("Riepilogo per stato: \(statusSummary)")
        }
        
        let urgentCount = exams.filter(\.isUrgent).count
        if urgentCount > 0 {
            lines.append("Di cui urgenti: \(urgentCount)")
        }
        
        lines.append("\n--- ESAMI (\(exams.count)) ---")
        
        for (index, exam) in exams.enumerated() {
            lines.append("")
            lines.append("==========")
            lines.append("ESAME \(index + 1) di \(exams.count)")
            lines.append("Nome: \(exam.name)")
            lines.append("Stato: \(exam.status.rawValue)")
            
            if exam.isUrgent { lines.append("Urgente: sì") }
            
            if let deadline = exam.deadline {
                let isOverdue = deadline < Date() && (exam.status == .pending || exam.status == .booked)
                lines.append("Scadenza: \(formatDate(deadline))\(isOverdue ? " ⚠️ SCADUTA" : "")")
            }
            
            if let location = exam.location, !location.isEmpty {
                lines.append("Luogo: \(location)")
            }
            
            if let preparation = exam.preparation, !preparation.isEmpty {
                lines.append("Preparazione: \(preparation)")
            }
            
            if let notes = exam.notes, !notes.isEmpty {
                lines.append("Note: \(notes)")
            }
            
            if let resultText = exam.resultText, !resultText.isEmpty {
                lines.append("Risultato: \(resultText)")
            }
            
            if let resultDate = exam.resultDate {
                lines.append("Data risultato: \(formatDate(resultDate))")
            }
            
            let docs = documentsByExamId[exam.id] ?? []
            if !docs.isEmpty {
                appendDocuments(docs, to: &lines, context: "esame")
            }
        }
        
        lines.append("\n--- FINE DATI ESAMI ---")
        lines.append("\nRispondi alle domande del genitore sugli esami usando le informazioni sopra.")
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("ExamContextBuilder all end exams=\(exams.count) chars=\(prompt.count)")
        return prompt
    }
    
    // MARK: - Shared helpers
    
    private static func appendDocuments(
        _ documents: [KBDocument],
        to lines: inout [String],
        context: String
    ) {
        let completed = documents.filter {
            $0.extractionStatus == .completed && $0.hasExtractedText
        }
        
        KBLog.ai.kbDebug("ExamContextBuilder appendDocuments total=\(documents.count) completed=\(completed.count)")
        
        guard !completed.isEmpty else {
            if !documents.isEmpty {
                lines.append("\nReferti allegati: \(documents.count) file presenti, testo non ancora estratto.")
                KBLog.ai.kbDebug("ExamContextBuilder: attachments present but not extracted count=\(documents.count)")
            }
            return
        }
        
        lines.append("\n--- DOCUMENTI / REFERTI ALLEGATI ---")
        
        var included = 0
        var skipped = 0
        
        for doc in completed {
            let cleanText = sanitizeExtractedText(doc.extractedText ?? "")
            guard !cleanText.isEmpty else {
                skipped += 1
                KBLog.ai.kbDebug("ExamContextBuilder skipped empty doc id=\(doc.id) title=\(doc.title)")
                continue
            }
            lines.append("\nDocumento: \(doc.title)")
            lines.append("Tipo: \(doc.mimeType)")
            lines.append("Testo estratto:")
            lines.append(cleanText)
            included += 1
            KBLog.ai.kbDebug("ExamContextBuilder included doc id=\(doc.id) chars=\(cleanText.count)")
        }
        
        KBLog.ai.kbInfo("ExamContextBuilder documents included=\(included) skipped=\(skipped)")
    }
    
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    private static func sanitizeExtractedText(_ text: String) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        KBLog.ai.kbDebug("ExamContextBuilder sanitize inputChars=\(text.count) outputChars=\(sanitized.count)")
        return sanitized
    }
}

