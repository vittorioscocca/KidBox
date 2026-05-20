//
//  ClinicalRecordBuilder.swift
//  KidBox
//

import Foundation

/// Testo strutturato per la cartella clinica PDF (visite, esami, scheda, vaccini, app Salute).
enum ClinicalRecordBuilder {

    static let refertoMaxChars = 2_000

    static func buildLines(
        subjectName: String,
        childBirthDate: Date?,
        profile: KBPediatricProfile?,
        healthSnapshot: KBHealthImportSnapshot?,
        healthSourceLabel: String,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam],
        documentsByExamId: [String: [KBDocument]],
        documentsByVisitId: [String: [KBDocument]],
        documentsByTreatmentId: [String: [KBDocument]]
    ) -> [String] {
        var lines: [String] = []

        lines.append("CARTELLA CLINICA")
        lines.append("Paziente: \(subjectName)")
        if let birth = childBirthDate ?? profile.flatMap({ _ in healthSnapshot?.birthDate }) {
            lines.append("Data di nascita: \(formatDate(birth))")
            let age = KBHealthAgeFormatting.ageDescription(from: birth)
            if !age.isEmpty { lines.append("Età: \(age)") }
        }
        lines.append("Generata il: \(formatDateTime(Date()))")
        lines.append("Documento prodotto da KidBox — solo per uso personale/familiare.")

        appendMedicalRecord(profile: profile, to: &lines)
        appendHealthApp(snapshot: healthSnapshot, sourceLabel: healthSourceLabel, to: &lines)
        appendTreatments(
            treatments,
            documentsByTreatmentId: documentsByTreatmentId,
            to: &lines
        )
        appendVaccines(vaccines, to: &lines)

        let sortedVisits = visits.sorted { $0.date > $1.date }
        appendVisits(
            sortedVisits,
            documentsByVisitId: documentsByVisitId,
            to: &lines
        )

        let sortedExams = exams.sorted {
            ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
        }
        appendExams(
            sortedExams,
            documentsByExamId: documentsByExamId,
            to: &lines
        )

        lines.append("\n--- FINE CARTELLA CLINICA ---")
        return lines
    }

    // MARK: - Scheda medica

    private static func appendMedicalRecord(
        profile: KBPediatricProfile?,
        to lines: inout [String]
    ) {
        lines.append("\n--- SCHEDA MEDICA ---")
        guard let p = profile else {
            lines.append("Nessuna scheda medica compilata.")
            return
        }
        if let g = p.bloodGroup, !g.isEmpty { lines.append("Gruppo sanguigno: \(g)") }
        if let a = p.allergies, !a.isEmpty { lines.append("Allergie: \(a)") }
        if let n = p.medicalNotes, !n.isEmpty { lines.append("Note mediche: \(n)") }

        if let name = p.doctorName, !name.isEmpty {
            var dl = "Pediatra / medico: \(name)"
            if let phone = p.doctorPhone, !phone.isEmpty { dl += " — Tel. \(phone)" }
            lines.append(dl)
        }
        if let email = p.doctorEmail, !email.isEmpty { lines.append("Email medico: \(email)") }
        if let addr = p.doctorAddress, !addr.isEmpty { lines.append("Studio: \(addr)") }

        let contacts = p.emergencyContacts
        if !contacts.isEmpty {
            lines.append("Contatti emergenza:")
            for c in contacts {
                var cl = "  • \(c.name)"
                if !c.phone.isEmpty { cl += " — \(c.phone)" }
                if !c.relation.isEmpty { cl += " (\(c.relation))" }
                lines.append(cl)
            }
        }
    }

    // MARK: - App Salute

    private static func appendHealthApp(
        snapshot: KBHealthImportSnapshot?,
        sourceLabel: String,
        to lines: inout [String]
    ) {
        lines.append("\n--- \(sourceLabel.uppercased()) ---")
        guard let s = snapshot, s.hasProfileFields || s.hasCardiacOrActivity else {
            lines.append("Nessun dato importato dall'app Salute.")
            return
        }
        if let synced = Optional(s.syncedAt) {
            lines.append("Ultimo aggiornamento dati: \(formatDateTime(synced))")
        }
        if let age = s.ageDescription { lines.append("Età (da app Salute): \(age)") }
        if let w = s.weightKg {
            var wl = String(format: "Peso: %.2f kg", w)
            if let at = s.weightMeasuredAt { wl += " (\(formatDate(at)))" }
            lines.append(wl)
        }
        if let bg = s.bloodGroup, !bg.isEmpty { lines.append("Gruppo sanguigno (app): \(bg)") }
        if let hr = s.heartRateBpm {
            lines.append(String(format: "Frequenza cardiaca: %.0f bpm", hr))
        }
        if let rhr = s.restingHeartRateBpm {
            lines.append(String(format: "Frequenza a riposo: %.0f bpm", rhr))
        }
        if let bp = s.bloodPressureDescription {
            lines.append("Pressione arteriosa: \(bp) mmHg")
        }
        if let o2 = s.oxygenSaturationPercent {
            lines.append(String(format: "Saturazione O₂: %.0f%%", o2))
        }
        if let vo2 = s.vo2Max {
            lines.append(String(format: "VO₂ max: %.1f", vo2))
        }
        if let steps = s.stepsToday, steps > 0 {
            lines.append("Passi oggi: \(steps)")
        }
        if let kcal = s.activeEnergyKcal {
            lines.append(String(format: "Energia attiva oggi: %.0f kcal", kcal))
        }

        if !s.recentWorkouts.isEmpty {
            lines.append("Allenamenti recenti:")
            for w in s.recentWorkouts.prefix(15) {
                var wl = "  • \(w.title) — \(formatDate(w.startedAt))"
                if let min = w.durationMinutes { wl += ", \(min) min" }
                lines.append(wl)
            }
        }
        if !s.recentECGs.isEmpty {
            lines.append("ECG recenti:")
            for e in s.recentECGs.prefix(10) {
                lines.append("  • \(formatDate(e.recordedAt)) — \(e.classificationLabel)")
            }
        }
        if !s.recentDailyActivity.isEmpty {
            lines.append("Attività giornaliera (ultimi giorni):")
            for d in s.recentDailyActivity.prefix(14) {
                var dl = "  • \(formatDate(d.day))"
                if let st = d.steps, st > 0 { dl += " — \(st) passi" }
                lines.append(dl)
            }
        }
    }

    // MARK: - Cure, vaccini, visite, esami (allineato a HealthContextBuilder)

    private static func appendTreatments(
        _ treatments: [KBTreatment],
        documentsByTreatmentId: [String: [KBDocument]],
        to lines: inout [String]
    ) {
        guard !treatments.isEmpty else { return }
        lines.append("\n--- CURE ATTIVE (\(treatments.count)) ---")
        for t in treatments {
            var line = "• \(t.drugName)"
            line += " — \(t.dosageValue, default: "%.0f") \(t.dosageUnit)"
            line += ", \(t.frequencyDisplayLabel)"
            if t.isLongTerm {
                line += ", lungo termine"
            } else if let end = t.endDate {
                line += " (fine: \(formatDate(end)))"
            }
            if let notes = t.notes, !notes.isEmpty { line += " — \(notes)" }
            lines.append(line)
            appendDocumentTexts(
                documentsByTreatmentId[t.id] ?? [],
                indent: "  ",
                to: &lines
            )
        }
    }

    private static func appendVaccines(_ vaccines: [KBVaccine], to lines: inout [String]) {
        guard !vaccines.isEmpty else { return }
        let sorted = vaccines.sorted {
            ($0.administeredDate ?? $0.scheduledDate ?? $0.createdAt) >
            ($1.administeredDate ?? $1.scheduledDate ?? $1.createdAt)
        }
        lines.append("\n--- VACCINI (\(sorted.count)) ---")
        for v in sorted {
            let displayName = v.commercialName.flatMap { $0.isEmpty ? nil : $0 } ?? v.vaccineType.displayName
            var line = "• \(displayName)"
            if let administered = v.administeredDate {
                line += " — somministrato il \(formatDate(administered))"
            } else if let scheduled = v.scheduledDate {
                line += " — programmato per \(formatDate(scheduled))"
            }
            if v.totalDoses > 1 { line += " (dose \(v.doseNumber)/\(v.totalDoses))" }
            if let lot = v.lotNumber, !lot.isEmpty { line += " — Lotto: \(lot)" }
            if let notes = v.notes, !notes.isEmpty { line += " — \(notes)" }
            lines.append(line)
        }
    }

    private static func appendVisits(
        _ visits: [KBMedicalVisit],
        documentsByVisitId: [String: [KBDocument]],
        to lines: inout [String]
    ) {
        guard !visits.isEmpty else { return }
        lines.append("\n--- VISITE MEDICHE (\(visits.count)) ---")
        for (index, visit) in visits.enumerated() {
            lines.append("")
            lines.append("VISITA \(index + 1) — \(formatDate(visit.date))")
            if !visit.reason.isEmpty { lines.append("Motivo: \(visit.reason)") }
            if let doctor = visit.doctorName, !doctor.isEmpty {
                var dl = "Medico: \(doctor)"
                if let spec = visit.doctorSpecialization { dl += " (\(spec.rawValue))" }
                lines.append(dl)
            }
            if let diagnosis = visit.diagnosis, !diagnosis.isEmpty {
                lines.append("Diagnosi: \(diagnosis)")
            }
            if let rec = visit.recommendations, !rec.isEmpty {
                lines.append("Raccomandazioni: \(rec)")
            }
            if let notes = visit.notes, !notes.isEmpty { lines.append("Note: \(notes)") }
            if let next = visit.nextVisitDate {
                lines.append("Prossima visita: \(formatDate(next))")
            }
            appendDocumentTexts(documentsByVisitId[visit.id] ?? [], indent: "  ", to: &lines)
        }
    }

    private static func appendExams(
        _ exams: [KBMedicalExam],
        documentsByExamId: [String: [KBDocument]],
        to lines: inout [String]
    ) {
        guard !exams.isEmpty else { return }
        lines.append("\n--- ANALISI ED ESAMI (\(exams.count)) ---")
        for exam in exams {
            var line = "• \(exam.name) [\(exam.status.rawValue)]"
            if exam.isUrgent { line += " [URGENTE]" }
            if let deadline = exam.deadline {
                line += " — scadenza: \(formatDate(deadline))"
            }
            lines.append(line)
            if let result = exam.resultText, !result.isEmpty {
                let clean = HealthAiDocumentText.prepareExtractedTextForAI(
                    result,
                    maxChars: refertoMaxChars
                )
                if !clean.isEmpty { lines.append("  Risultato: \(clean)") }
            }
            appendDocumentTexts(documentsByExamId[exam.id] ?? [], indent: "  ", to: &lines)
        }
    }

    private static func appendDocumentTexts(
        _ docs: [KBDocument],
        indent: String,
        to lines: inout [String]
    ) {
        for doc in docs where doc.extractionStatus == .completed && doc.hasExtractedText {
            let clean = HealthAiDocumentText.prepareExtractedTextForAI(
                doc.extractedText,
                maxChars: refertoMaxChars
            )
            guard !clean.isEmpty else { continue }
            lines.append("\(indent)Referto (\(doc.title)):")
            for sub in clean.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("\(indent)  \(sub)")
            }
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    private static func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: date)
    }
}
