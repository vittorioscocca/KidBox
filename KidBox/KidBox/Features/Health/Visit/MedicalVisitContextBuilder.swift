//
//  MedicalVisitContextBuilder.swift
//  KidBox
//

import Foundation

/// Builds the AI system prompt from a `KBMedicalVisit`, child context,
/// treatments and extracted document text.
enum MedicalVisitContextBuilder {
    
    static func buildSystemPrompt(
        visit: KBMedicalVisit,
        child: KBChild,
        treatments: [KBTreatment] = [],
        documents: [KBDocument] = [],
        childAge: String? = nil
    ) -> String {
        
        KBLog.ai.kbInfo("Build system prompt start visitId=\(visit.id) childId=\(child.id) treatments=\(treatments.count) documents=\(documents.count)")
        
        let ageStr = childAge ?? computeAge(birthDate: child.birthDate)
        var lines: [String] = []
        
        lines.append("""
        Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.
        Il tuo ruolo è spiegare in modo chiaro e comprensibile le informazioni relative a una visita medica pediatrica.
        
        REGOLE IMPORTANTI:
        - Non fare diagnosi e non sostituirti al medico.
        - Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente di consultare il proprio medico.
        - Usa un linguaggio semplice, adatto a un genitore non esperto.
        - Puoi spiegare termini medici, farmaci, terapie, esami prescritti e contenuto dei referti allegati.
        - Se nel contesto sono presenti testi estratti da documenti o referti, usali per spiegare meglio il contenuto.
        - Se un testo estratto sembra incompleto o poco chiaro, dillo esplicitamente.
        - Rispondi sempre in italiano.
        """)
        
        lines.append("\n--- DATI VISITA ---")
        
        lines.append("Bambino: \(child.name)")
        if !ageStr.isEmpty {
            lines.append("Età: \(ageStr)")
            KBLog.ai.kbDebug("Computed child age=\(ageStr)")
        } else {
            KBLog.ai.kbDebug("Child age unavailable for childId=\(child.id)")
        }
        
        lines.append("Data visita: \(formatDate(visit.date))")
        
        if !visit.reason.isEmpty {
            lines.append("Motivo della visita: \(visit.reason)")
            KBLog.ai.kbDebug("Visit reason included")
        }
        
        if let doctor = visit.doctorName, !doctor.isEmpty {
            var doctorLine = "Medico: \(doctor)"
            if let spec = visit.doctorSpecialization {
                doctorLine += " (\(spec.rawValue))"
            }
            lines.append(doctorLine)
            KBLog.ai.kbDebug("Doctor info included")
        }
        
        if let diagnosis = visit.diagnosis, !diagnosis.isEmpty {
            lines.append("\nDiagnosi:\n\(diagnosis)")
            KBLog.ai.kbDebug("Diagnosis included chars=\(diagnosis.count)")
        }
        
        if let recommendations = visit.recommendations, !recommendations.isEmpty {
            lines.append("\nRaccomandazioni:\n\(recommendations)")
            KBLog.ai.kbDebug("Recommendations included chars=\(recommendations.count)")
        }
        
        if !treatments.isEmpty {
            lines.append("\nFarmaci programmati (\(treatments.count)):")
            for t in treatments {
                var line = "- \(t.drugName)"
                line += ", \(t.dosageValue, default: "%.0f") \(t.dosageUnit)"
                line += ", \(t.dailyFrequency)x al giorno"
                line += t.isLongTerm ? ", lungo termine" : ", \(t.durationDays) giorni"
                if let notes = t.notes, !notes.isEmpty {
                    line += " (\(notes))"
                }
                lines.append(line)
            }
            KBLog.ai.kbDebug("Scheduled treatments included count=\(treatments.count)")
        }
        
        let drugs = visit.asNeededDrugs
        if !drugs.isEmpty {
            lines.append("\nFarmaci al bisogno:")
            for drug in drugs {
                var line = "- \(drug.drugName), \(drug.dosageValue, default: "%.0f") \(drug.dosageUnit)"
                if let instructions = drug.instructions, !instructions.isEmpty {
                    line += " (\(instructions))"
                }
                lines.append(line)
            }
            KBLog.ai.kbDebug("As-needed drugs included count=\(drugs.count)")
        }
        
        let therapies = visit.therapyTypes
        if !therapies.isEmpty {
            lines.append("\nTerapie prescritte: \(therapies.map { $0.rawValue }.joined(separator: ", "))")
            KBLog.ai.kbDebug("Therapies included count=\(therapies.count)")
        }
        
        let exams = visit.prescribedExams
        if !exams.isEmpty {
            lines.append("\nEsami prescritti:")
            for exam in exams {
                var line = "- \(exam.name)"
                if exam.isUrgent { line += " [URGENTE]" }
                if let deadline = exam.deadline {
                    line += " — entro \(formatDate(deadline))"
                }
                if let prep = exam.preparation, !prep.isEmpty {
                    line += " (preparazione: \(prep))"
                }
                lines.append(line)
            }
            KBLog.ai.kbDebug("Prescribed exams included count=\(exams.count)")
        }
        
        if let notes = visit.notes, !notes.isEmpty {
            lines.append("\nNote cliniche:\n\(notes)")
            KBLog.ai.kbDebug("Clinical notes included chars=\(notes.count)")
        }
        
        if let nextDate = visit.nextVisitDate {
            var nextLine = "\nProssima visita: \(formatDate(nextDate))"
            if let reason = visit.nextVisitReason, !reason.isEmpty {
                nextLine += " — \(reason)"
            }
            lines.append(nextLine)
            KBLog.ai.kbDebug("Next visit included")
        }
        
        let completedDocuments = documents.filter {
            $0.extractionStatus == .completed && $0.hasExtractedText
        }
        
        KBLog.ai.kbDebug("Completed extracted documents count=\(completedDocuments.count)")
        
        if !completedDocuments.isEmpty {
            lines.append("\n--- DOCUMENTI / REFERTI ALLEGATI ---")
            
            var includedDocs = 0
            var skippedDocs = 0
            
            for doc in completedDocuments {
                let cleanText = sanitizeExtractedText(doc.extractedText ?? "")
                
                guard !cleanText.isEmpty else {
                    skippedDocs += 1
                    KBLog.ai.kbDebug("Skipped empty extracted text for document id=\(doc.id) title=\(doc.title)")
                    continue
                }
                
                lines.append("\nDocumento: \(doc.title)")
                lines.append("Tipo: \(doc.mimeType)")
                lines.append("Testo estratto:")
                lines.append(cleanText)
                
                includedDocs += 1
                KBLog.ai.kbDebug("Included extracted document id=\(doc.id) title=\(doc.title) chars=\(cleanText.count)")
            }
            
            KBLog.ai.kbInfo("Document extraction section built included=\(includedDocs) skipped=\(skippedDocs)")
            
        } else if !visit.photoURLs.isEmpty {
            lines.append("\nReferti allegati: \(visit.photoURLs.count) immagine/i presenti, ma testo non ancora estratto.")
            KBLog.ai.kbInfo("Legacy image fallback used photoCount=\(visit.photoURLs.count)")
        } else {
            KBLog.ai.kbDebug("No extracted documents and no legacy photos for visitId=\(visit.id)")
        }
        
        lines.append("\n--- FINE DATI VISITA ---")
        lines.append("\nRispondi alle domande del genitore sulla visita usando le informazioni sopra.")
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("Build system prompt completed visitId=\(visit.id) chars=\(prompt.count)")
        
        return prompt
    }
    
    // MARK: - Private helpers
    
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    private static func computeAge(birthDate: Date?) -> String {
        guard let birthDate else {
            KBLog.ai.kbDebug("computeAge: missing birthDate")
            return ""
        }
        
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: birthDate, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        
        let result: String
        if years == 0 {
            result = "\(months) \(months == 1 ? "mese" : "mesi")"
        } else if months == 0 {
            result = "\(years) \(years == 1 ? "anno" : "anni")"
        } else {
            result = "\(years) \(years == 1 ? "anno" : "anni") e \(months) \(months == 1 ? "mese" : "mesi")"
        }
        
        KBLog.ai.kbDebug("computeAge: result=\(result)")
        return result
    }
    
    private static func sanitizeExtractedText(_ text: String) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        
        KBLog.ai.kbDebug("sanitizeExtractedText: inputChars=\(text.count) outputChars=\(sanitized.count)")
        return sanitized
    }
}
