//
//  MedicalVisitContextBuilder.swift
//  KidBox
//

import Foundation

/// Builds the AI system prompt from a `KBMedicalVisit`, child context and treatments.
enum MedicalVisitContextBuilder {
    
    static func buildSystemPrompt(
        visit: KBMedicalVisit,
        child: KBChild,
        treatments: [KBTreatment] = [],
        childAge: String? = nil
    ) -> String {
        
        let ageStr = childAge ?? computeAge(birthDate: child.birthDate)
        var lines: [String] = []
        
        lines.append("""
        Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.
        Il tuo ruolo è spiegare in modo chiaro e comprensibile le informazioni relative a una visita medica pediatrica.
        
        REGOLE IMPORTANTI:
        - Non fare diagnosi e non sostituirti al medico.
        - Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente di consultare il proprio medico.
        - Usa un linguaggio semplice, adatto a un genitore non esperto.
        - Puoi spiegare termini medici, farmaci, terapie ed esami prescritti.
        - Se sono presenti immagini di referti, analizzale e spiegane il contenuto.
        - Rispondi sempre in italiano.
        """)
        
        lines.append("\n--- DATI VISITA ---")
        
        lines.append("Bambino: \(child.name)")
        if !ageStr.isEmpty { lines.append("Età: \(ageStr)") }
        
        lines.append("Data visita: \(formatDate(visit.date))")
        
        if !visit.reason.isEmpty {
            lines.append("Motivo della visita: \(visit.reason)")
        }
        
        if let doctor = visit.doctorName, !doctor.isEmpty {
            var doctorLine = "Medico: \(doctor)"
            if let spec = visit.doctorSpecialization {
                doctorLine += " (\(spec.rawValue))"
            }
            lines.append(doctorLine)
        }
        
        if let diagnosis = visit.diagnosis, !diagnosis.isEmpty {
            lines.append("\nDiagnosi:\n\(diagnosis)")
        }
        
        if let recommendations = visit.recommendations, !recommendations.isEmpty {
            lines.append("\nRaccomandazioni:\n\(recommendations)")
        }
        
        // Farmaci programmati (KBTreatment completi)
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
        }
        
        // Farmaci al bisogno
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
        }
        
        // Terapie
        let therapies = visit.therapyTypes
        if !therapies.isEmpty {
            lines.append("\nTerapie prescritte: \(therapies.map { $0.rawValue }.joined(separator: ", "))")
        }
        
        // Esami prescritti
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
        }
        
        if let notes = visit.notes, !notes.isEmpty {
            lines.append("\nNote cliniche:\n\(notes)")
        }
        
        if let nextDate = visit.nextVisitDate {
            var nextLine = "\nProssima visita: \(formatDate(nextDate))"
            if let reason = visit.nextVisitReason, !reason.isEmpty {
                nextLine += " — \(reason)"
            }
            lines.append(nextLine)
        }
        
        if !visit.photoURLs.isEmpty {
            lines.append("\nReferti allegati: \(visit.photoURLs.count) immagine/i allegate a questa visita.")
        }
        
        lines.append("\n--- FINE DATI VISITA ---")
        lines.append("\nRispondi alle domande del genitore sulla visita usando le informazioni sopra.")
        
        return lines.joined(separator: "\n")
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
        guard let birthDate else { return "" }
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: birthDate, to: Date())
        let years  = components.year  ?? 0
        let months = components.month ?? 0
        
        if years == 0 {
            return "\(months) \(months == 1 ? "mese" : "mesi")"
        } else if months == 0 {
            return "\(years) \(years == 1 ? "anno" : "anni")"
        } else {
            return "\(years) \(years == 1 ? "anno" : "anni") e \(months) \(months == 1 ? "mese" : "mesi")"
        }
    }
}
