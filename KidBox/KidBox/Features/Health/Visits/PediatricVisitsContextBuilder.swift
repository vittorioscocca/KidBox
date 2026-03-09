//
//  PediatricVisitsContextBuilder.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import Foundation

enum PediatricVisitsContextBuilder {
    
    static func buildSystemPrompt(
        child: KBChild,
        visits: [KBMedicalVisit],
        documentsByVisitId: [String: [KBDocument]],
        treatmentsByVisitId: [String: [KBTreatment]]
    ) -> String {
        
        let ageStr = computeAge(birthDate: child.birthDate)
        var lines: [String] = []
        
        lines.append("""
        Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.
        Il tuo ruolo è spiegare in modo chiaro e comprensibile l'insieme delle visite mediche pediatriche del bambino.
        
        REGOLE IMPORTANTI:
        - Non fare diagnosi e non sostituirti al medico.
        - Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente di consultare il medico.
        - Usa un linguaggio semplice, adatto a un genitore non esperto.
        - Puoi aiutare a capire andamento clinico, visite, farmaci, esami, raccomandazioni e referti allegati.
        - Se nei documenti ci sono testi estratti, usali.
        - Se un testo estratto sembra incompleto o ambiguo, dillo chiaramente.
        - Rispondi sempre in italiano.
        """)
        
        lines.append("\n--- PROFILO BAMBINO ---")
        lines.append("Nome: \(child.name)")
        if !ageStr.isEmpty {
            lines.append("Età: \(ageStr)")
        }
        
        lines.append("\n--- VISITE MEDICHE (\(visits.count)) ---")
        
        for (index, visit) in visits.enumerated() {
            lines.append("\n### VISITA \(index + 1)")
            lines.append("Data visita: \(formatDate(visit.date))")
            
            if !visit.reason.isEmpty {
                lines.append("Motivo: \(visit.reason)")
            }
            
            if let doctor = visit.doctorName, !doctor.isEmpty {
                var doctorLine = "Medico: \(doctor)"
                if let spec = visit.doctorSpecialization {
                    doctorLine += " (\(spec.rawValue))"
                }
                lines.append(doctorLine)
            }
            
            if let diagnosis = visit.diagnosis, !diagnosis.isEmpty {
                lines.append("Diagnosi: \(diagnosis)")
            }
            
            if let recommendations = visit.recommendations, !recommendations.isEmpty {
                lines.append("Raccomandazioni: \(recommendations)")
            }
            
            let treatments = treatmentsByVisitId[visit.id] ?? []
            if !treatments.isEmpty {
                lines.append("Farmaci programmati:")
                for t in treatments {
                    var line = "- \(t.drugName), \(t.dosageValue, default: "%.0f") \(t.dosageUnit)"
                    line += ", \(t.dailyFrequency)x al giorno"
                    line += t.isLongTerm ? ", lungo termine" : ", \(t.durationDays) giorni"
                    if let notes = t.notes, !notes.isEmpty {
                        line += " (\(notes))"
                    }
                    lines.append(line)
                }
            }
            
            if !visit.asNeededDrugs.isEmpty {
                lines.append("Farmaci al bisogno:")
                for drug in visit.asNeededDrugs {
                    var line = "- \(drug.drugName), \(drug.dosageValue, default: "%.0f") \(drug.dosageUnit)"
                    if let instructions = drug.instructions, !instructions.isEmpty {
                        line += " (\(instructions))"
                    }
                    lines.append(line)
                }
            }
            
            if !visit.therapyTypes.isEmpty {
                lines.append("Terapie: \(visit.therapyTypes.map(\.rawValue).joined(separator: ", "))")
            }
            
            if !visit.prescribedExams.isEmpty {
                lines.append("Esami prescritti:")
                for exam in visit.prescribedExams {
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
            }
            
            if let notes = visit.notes, !notes.isEmpty {
                lines.append("Note: \(notes)")
            }
            
            if let nextDate = visit.nextVisitDate {
                var nextLine = "Prossima visita: \(formatDate(nextDate))"
                if let reason = visit.nextVisitReason, !reason.isEmpty {
                    nextLine += " — \(reason)"
                }
                lines.append(nextLine)
            }
            
            let docs = (documentsByVisitId[visit.id] ?? []).filter {
                $0.extractionStatus == .completed && $0.hasExtractedText
            }
            
            if !docs.isEmpty {
                lines.append("Referti/documenti allegati:")
                for doc in docs {
                    let clean = sanitizeExtractedText(doc.extractedText ?? "")
                    guard !clean.isEmpty else { continue }
                    lines.append("Documento: \(doc.title)")
                    lines.append(clean)
                }
            }
        }
        
        lines.append("\n--- FINE CONTESTO ---")
        lines.append("Rispondi alle domande del genitore usando le informazioni sopra.")
        
        return lines.joined(separator: "\n")
    }
    
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    private static func computeAge(birthDate: Date?) -> String {
        guard let birthDate else { return "" }
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: birthDate, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        
        if years == 0 {
            return "\(months) \(months == 1 ? "mese" : "mesi")"
        } else if months == 0 {
            return "\(years) \(years == 1 ? "anno" : "anni")"
        } else {
            return "\(years) \(years == 1 ? "anno" : "anni") e \(months) \(months == 1 ? "mese" : "mesi")"
        }
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
