//
//  PediatricAdvancedContextBuilder.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//

//
//  PediatricAdvancedContextBuilder.swift
//  KidBox
//
//  Context builder per l'analisi longitudinale della salute di un soggetto
//  (bambino o membro adulto della famiglia).
//
//  Per i bambini include:
//  - Profilo medico (gruppo sanguigno, allergie, pediatra)
//  - Trend crescita (peso/altezza con età al momento della misura)
//  - Storico visite per specialista e stagionalità malattie
//  - Farmaci e cure nel tempo
//  - Esami con risultati
//  - Vaccini somministrati e pianificati
//
//  Per i membri adulti include:
//  - Storico visite e diagnosi
//  - Cure attive e passate
//  - Esami con risultati
//  (senza sezioni crescita/vaccini/profilo pediatrico)
//
//  Usato da HealthAIChatViewModel e PlanningAIChatViewModel
//  quando si chiede "come sta X?" o "dimmi la storia medica di X".
//

import Foundation

// MARK: - Subject type

enum PediatricAdvancedSubject {
    case child(KBChild, profile: KBPediatricProfile?)
    case member(name: String, birthDate: Date?)
}

// MARK: - Input

struct PediatricAdvancedInput {
    let familyId:   String
    let subject:    PediatricAdvancedSubject
    let subjectId:  String   // childId o memberId
    
    // Dati sanitari (filtrati per subjectId dal caller)
    let allVisits:    [KBMedicalVisit]   // tutte, non cancellate, ordinate per data desc
    let allExams:     [KBMedicalExam]    // tutti, non cancellati
    let allTreatments:[KBTreatment]      // tutti (attivi e passati)
    let allVaccines:  [KBVaccine]        // solo per bambini; passare [] per adulti
    
    /// Finestra storica in giorni (default 365 = 1 anno)
    let historicDays: Int
    
    init(
        familyId:      String,
        subject:       PediatricAdvancedSubject,
        subjectId:     String,
        allVisits:     [KBMedicalVisit]  = [],
        allExams:      [KBMedicalExam]   = [],
        allTreatments: [KBTreatment]     = [],
        allVaccines:   [KBVaccine]       = [],
        historicDays:  Int               = 365
    ) {
        self.familyId      = familyId
        self.subject       = subject
        self.subjectId     = subjectId
        self.allVisits     = allVisits
        self.allExams      = allExams
        self.allTreatments = allTreatments
        self.allVaccines   = allVaccines
        self.historicDays  = min(max(historicDays, 30), 1825) // 30d – 5y
    }
    
    var subjectName: String {
        switch subject {
        case .child(let c, _):   return c.name
        case .member(let n, _):  return n
        }
    }
    
    var isChild: Bool {
        if case .child = subject { return true }
        return false
    }
}

// MARK: - Builder

enum PediatricAdvancedContextBuilder {
    
    // MARK: - Entry point
    
    static func buildSystemPrompt(input: PediatricAdvancedInput) -> String {
        let now     = Date()
        let cutoff  = Calendar.current.date(byAdding: .day, value: -input.historicDays, to: now) ?? now
        
        KBLog.ai.kbInfo("""
        PediatricAdvancedContextBuilder start \
        subject=\(input.subjectName) isChild=\(input.isChild) \
        visits=\(input.allVisits.count) exams=\(input.allExams.count) \
        treatments=\(input.allTreatments.count) vaccines=\(input.allVaccines.count)
        """)
        
        var lines: [String] = []
        
        // ── Role ─────────────────────────────────────────────────────
        lines.append(buildRole(input: input))
        
        // ── Profilo base ─────────────────────────────────────────────
        appendSubjectProfile(input: input, now: now, to: &lines)
        
        // ── Storico visite ───────────────────────────────────────────
        let recentVisits = input.allVisits
            .filter { !$0.isDeleted && $0.date >= cutoff }
            .sorted { $0.date > $1.date }
        appendVisitHistory(recentVisits, input: input, to: &lines)
        
        // ── Stagionalità malattie (solo bambini, ultimi 2 anni) ──────
        if input.isChild {
            let twoYearsCutoff = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? cutoff
            let longVisits = input.allVisits.filter { !$0.isDeleted && $0.date >= twoYearsCutoff }
            appendSeasonality(longVisits, to: &lines)
        }
        
        // ── Specialisti frequentati ───────────────────────────────────
        appendSpecialists(input.allVisits.filter { !$0.isDeleted }, to: &lines)
        
        // ── Trattamenti / farmaci ─────────────────────────────────────
        appendTreatmentHistory(input.allTreatments.filter { !$0.isDeleted }, now: now, to: &lines)
        
        // ── Esami ────────────────────────────────────────────────────
        appendExamHistory(input.allExams.filter { !$0.isDeleted }, cutoff: cutoff, to: &lines)
        
        // ── Vaccini (solo bambini) ───────────────────────────────────
        if input.isChild && !input.allVaccines.isEmpty {
            appendVaccines(input.allVaccines.filter { !$0.isDeleted }, to: &lines)
        }
        
        // ── Trend crescita (solo bambini) ────────────────────────────
        if case .child(let child, _) = input.subject {
            appendGrowthTrend(child: child, visits: input.allVisits, now: now, to: &lines)
        }
        
        lines.append("\n--- FINE PROFILO SANITARIO ---")
        lines.append("""
        \nRispondi alle domande sulla salute di \(input.subjectName) usando le informazioni sopra.
        Non dare consigli medici vincolanti — per decisioni cliniche invita a consultare il medico.
        Parla in italiano con tono caldo e informativo.
        """)
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("PediatricAdvancedContextBuilder done chars=\(prompt.count)")
        return prompt
    }
    
    // MARK: - Role
    
    private static func buildRole(input: PediatricAdvancedInput) -> String {
        switch input.subject {
        case .child(let child, _):
            let age = child.ageDescription.isEmpty ? "" : ", \(child.ageDescription)"
            return """
            Sei l'assistente sanitario AI di KidBox per \(child.name)\(age).
            Hai accesso allo storico medico completo: visite, diagnosi, farmaci, esami e vaccini.
            """
        case .member(let name, let bd):
            let age = bd.map { birthDateToAge($0) }.map { ", \($0)" } ?? ""
            return """
            Sei l'assistente sanitario AI di KidBox per \(name)\(age).
            Hai accesso allo storico medico: visite, diagnosi, farmaci ed esami.
            """
        }
    }
    
    // MARK: - Subject profile
    
    private static func appendSubjectProfile(
        input: PediatricAdvancedInput,
        now:   Date,
        to lines: inout [String]
    ) {
        lines.append("\n--- PROFILO ---")
        
        switch input.subject {
        case .child(let child, let profile):
            if let bd = child.birthDate {
                lines.append("Data di nascita: \(formatDate(bd)) (\(child.ageDescription))")
            }
            if let w = child.weightKg {
                lines.append("Peso attuale: \(String(format: "%.1f", w)) kg")
            }
            if let h = child.heightCm {
                lines.append("Altezza attuale: \(String(format: "%.0f", h)) cm")
            }
            if let p = profile {
                if let bg = p.bloodGroup,    !bg.isEmpty  { lines.append("Gruppo sanguigno: \(bg)") }
                if let al = p.allergies,     !al.isEmpty  { lines.append("Allergie: \(al)") }
                if let mn = p.medicalNotes,  !mn.isEmpty  { lines.append("Note mediche: \(mn)") }
                if let dn = p.doctorName,    !dn.isEmpty  { lines.append("Pediatra: \(dn)") }
            }
            
        case .member(let name, let bd):
            if let bd {
                lines.append("Data di nascita: \(formatDate(bd)) (\(birthDateToAge(bd)))")
            }
        }
    }
    
    // MARK: - Visit history
    
    private static func appendVisitHistory(
        _ visits: [KBMedicalVisit],
        input:    PediatricAdvancedInput,
        to lines: inout [String]
    ) {
        guard !visits.isEmpty else {
            lines.append("\n--- VISITE: nessuna visita nel periodo ---")
            return
        }
        lines.append("\n--- VISITE RECENTI (\(visits.count)) ---")
        for v in visits.prefix(20) {
            var line = "• \(formatDate(v.date))"
            if let spec = v.doctorSpecialization { line += " [\(spec.displayName)]" }
            if !v.reason.isEmpty { line += " — \(v.reason)" }
            if let diag = v.diagnosis, !diag.isEmpty { line += " → \(diag)" }
            if let rec = v.recommendations, !rec.isEmpty { line += " (rec: \(String(rec.prefix(80))))" }
            lines.append(line)
        }
    }
    
    // MARK: - Seasonality
    
    private static func appendSeasonality(
        _ visits: [KBMedicalVisit],
        to lines: inout [String]
    ) {
        guard visits.count >= 3 else { return }
        
        // Raggruppa per stagione
        var seasons: [String: [String]] = [
            "Primavera (Mar-Mag)": [],
            "Estate (Giu-Ago)":    [],
            "Autunno (Set-Nov)":   [],
            "Inverno (Dic-Feb)":   []
        ]
        
        for v in visits {
            let month = Calendar.current.component(.month, from: v.date)
            let key: String
            switch month {
            case 3...5:  key = "Primavera (Mar-Mag)"
            case 6...8:  key = "Estate (Giu-Ago)"
            case 9...11: key = "Autunno (Set-Nov)"
            default:     key = "Inverno (Dic-Feb)"
            }
            if !v.reason.isEmpty { seasons[key]?.append(v.reason) }
        }
        
        let nonEmpty = seasons.filter { !$0.value.isEmpty }
        guard !nonEmpty.isEmpty else { return }
        
        lines.append("\n--- STAGIONALITÀ MALATTIE (ultimi 2 anni) ---")
        for (season, reasons) in nonEmpty.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(season): \(reasons.count) visit\(reasons.count == 1 ? "a" : "e")")
            // Top 3 motivi più frequenti
            let freq = Dictionary(reasons.map { ($0, 1) }, uniquingKeysWith: +)
                .sorted { $0.value > $1.value }
                .prefix(3)
            for (reason, count) in freq {
                lines.append("    → \(reason) (\(count)×)")
            }
        }
    }
    
    // MARK: - Specialists
    
    private static func appendSpecialists(
        _ visits: [KBMedicalVisit],
        to lines: inout [String]
    ) {
        let specs = Dictionary(
            grouping: visits.compactMap { $0.doctorSpecialization },
            by: { $0 }
        ).mapValues { $0.count }
        guard !specs.isEmpty else { return }
        
        lines.append("\n--- SPECIALISTI FREQUENTATI ---")
        for (spec, count) in specs.sorted(by: { $0.value > $1.value }) {
            lines.append("  • \(spec.displayName): \(count) visit\(count == 1 ? "a" : "e")")
        }
    }
    
    // MARK: - Treatments
    
    private static func appendTreatmentHistory(
        _ treatments: [KBTreatment],
        now: Date,
        to lines: inout [String]
    ) {
        guard !treatments.isEmpty else { return }
        
        let active   = treatments.filter { $0.isActive }
        let inactive = treatments.filter { !$0.isActive }
        
        lines.append("\n--- FARMACI E CURE ---")
        
        if !active.isEmpty {
            lines.append("Attivi ora (\(active.count)):")
            for t in active.prefix(8) {
                var line = "  • \(t.drugName)"
                line += " \(String(format: "%.1f", t.dosageValue)) \(t.dosageUnit)"
                line += " · \(t.scheduleTimes.count) dose/die"
                if let end = t.endDate { line += " · fino al \(formatDate(end))" }
                lines.append(line)
            }
        }
        
        if !inactive.isEmpty {
            lines.append("Storici (\(inactive.count)):")
            for t in inactive.prefix(10) {
                var line = "  • \(t.drugName)"
                line += " dal \(formatDate(t.startDate))" 
                if let end   = t.endDate   { line += " al \(formatDate(end))" }
                lines.append(line)
            }
        }
    }
    
    // MARK: - Exams
    
    private static func appendExamHistory(
        _ exams:  [KBMedicalExam],
        cutoff:   Date,
        to lines: inout [String]
    ) {
        guard !exams.isEmpty else { return }
        
        let recent = exams.filter { ($0.deadline ?? $0.updatedAt) >= cutoff }
            .sorted { ($0.deadline ?? $0.updatedAt) > ($1.deadline ?? $1.updatedAt) }
        
        guard !recent.isEmpty else { return }
        lines.append("\n--- ESAMI (\(recent.count) nel periodo) ---")
        for e in recent.prefix(15) {
            var line = "• \(e.name)"
            if let dl = e.deadline { line += " — scadenza \(formatDate(dl))" }
            line += " [\(e.status.rawValue)]"
            if let res = e.resultText, !res.isEmpty {
                line += " → \(String(res.prefix(100)))"
            }
            if e.isUrgent { line += " ⚠️ urgente" }
            lines.append(line)
        }
    }
    
    // MARK: - Vaccines
    
    private static func appendVaccines(
        _ vaccines: [KBVaccine],
        to lines:   inout [String]
    ) {
        let administered = vaccines.filter { $0.status == .administered }
            .sorted { ($0.administeredDate ?? .distantPast) > ($1.administeredDate ?? .distantPast) }
        let planned = vaccines.filter { $0.status == .scheduled || $0.status == .planned }
        
        lines.append("\n--- VACCINI ---")
        
        if !administered.isEmpty {
            lines.append("Somministrati (\(administered.count)):")
            for v in administered.prefix(10) {
                var line = "  • \(v.vaccineType.displayName)"
                line += " dose \(v.doseNumber)/\(v.totalDoses)"
                if let d = v.administeredDate { line += " — \(formatDate(d))" }
                if let cn = v.commercialName, !cn.isEmpty { line += " (\(cn))" }
                lines.append(line)
            }
        }
        
        if !planned.isEmpty {
            lines.append("Pianificati/programmati (\(planned.count)):")
            for v in planned.prefix(5) {
                var line = "  • \(v.vaccineType.displayName)"
                line += " dose \(v.doseNumber)/\(v.totalDoses)"
                if let d = v.scheduledDate { line += " — \(formatDate(d))" }
                lines.append(line)
            }
        }
    }
    
    // MARK: - Growth trend
    
    private static func appendGrowthTrend(
        child:   KBChild,
        visits:  [KBMedicalVisit],
        now:     Date,
        to lines: inout [String]
    ) {
        guard let birthDate = child.birthDate else { return }
        
        // Peso e altezza attuali da KBChild
        var dataPoints: [(date: Date, weightKg: Double?, heightCm: Double?)] = []
        if child.weightKg != nil || child.heightCm != nil {
            dataPoints.append((date: now, weightKg: child.weightKg, heightCm: child.heightCm))
        }
        
        // Eventuale misura implicita da note visite (in futuro si potrebbe
        // estendere KBMedicalVisit con campi peso/altezza rilevati in visita)
        
        guard !dataPoints.isEmpty || child.weightKg != nil || child.heightCm != nil else { return }
        
        lines.append("\n--- CRESCITA ---")
        
        let ageMonths = Calendar.current.dateComponents([.month], from: birthDate, to: now).month ?? 0
        
        if let w = child.weightKg {
            let percentile = estimateWeightPercentile(weightKg: w, ageMonths: ageMonths, birthDate: birthDate)
            var line = "Peso: \(String(format: "%.1f", w)) kg"
            if let p = percentile { line += " (circa \(p)° percentile OMS)" }
            lines.append(line)
        }
        
        if let h = child.heightCm {
            let percentile = estimateHeightPercentile(heightCm: h, ageMonths: ageMonths, birthDate: birthDate)
            var line = "Altezza: \(String(format: "%.0f", h)) cm"
            if let p = percentile { line += " (circa \(p)° percentile OMS)" }
            lines.append(line)
        }
        
        // BMI se disponibili entrambi
        if let w = child.weightKg, let h = child.heightCm, h > 0 {
            let hm  = h / 100.0
            let bmi = w / (hm * hm)
            if let ageYears = child.ageYears, ageYears >= 2 {
                lines.append("BMI: \(String(format: "%.1f", bmi))")
            }
        }
    }
    
    // MARK: - WHO percentile estimates (semplificati)
    
    /// Stima grossolana del percentile OMS peso per età.
    /// Basata su valori mediani OMS 0-60 mesi. NON è un riferimento clinico.
    private static func estimateWeightPercentile(
        weightKg:  Double,
        ageMonths: Int,
        birthDate: Date
    ) -> Int? {
        // Mediane OMS approssimative per maschi (conservativo)
        // months: 0, 6, 12, 18, 24, 36, 48, 60
        let medians: [(months: Int, p50: Double, p10: Double, p90: Double)] = [
            (0,  3.3,  2.5,  4.2),
            (6,  7.9,  6.5,  9.4),
            (12, 9.7,  8.1, 11.4),
            (18, 11.1, 9.2, 13.1),
            (24, 12.2,10.1, 14.5),
            (36, 14.3,11.8, 17.0),
            (48, 16.3,13.4, 19.8),
            (60, 18.3,15.0, 22.5)
        ]
        guard ageMonths >= 0, ageMonths <= 72 else { return nil }
        let closest = medians.min(by: { abs($0.months - ageMonths) < abs($1.months - ageMonths) })!
        if      weightKg < closest.p10 { return 10 }
        else if weightKg < closest.p50 { return 25 }
        else if weightKg < closest.p90 { return 75 }
        else                            { return 90 }
    }
    
    /// Stima grossolana del percentile OMS altezza per età.
    private static func estimateHeightPercentile(
        heightCm:  Double,
        ageMonths: Int,
        birthDate: Date
    ) -> Int? {
        let medians: [(months: Int, p50: Double, p10: Double, p90: Double)] = [
            (0,  49.9, 46.8, 53.0),
            (6,  67.6, 64.4, 70.8),
            (12, 75.7, 72.1, 79.4),
            (18, 82.3, 78.3, 86.4),
            (24, 87.8, 83.4, 92.2),
            (36, 96.1, 91.2,101.0),
            (48,103.3, 97.9,108.8),
            (60,110.0,104.1,115.9)
        ]
        guard ageMonths >= 0, ageMonths <= 72 else { return nil }
        let closest = medians.min(by: { abs($0.months - ageMonths) < abs($1.months - ageMonths) })!
        if      heightCm < closest.p10 { return 10 }
        else if heightCm < closest.p50 { return 25 }
        else if heightCm < closest.p90 { return 75 }
        else                            { return 90 }
    }
    
    // MARK: - Formatting
    
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "it_IT")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
    
    static func birthDateToAge(_ date: Date) -> String {
        let comps  = Calendar.current.dateComponents([.year, .month], from: date, to: Date())
        let years  = comps.year  ?? 0
        let months = comps.month ?? 0
        if years  > 0 { return "\(years) ann\(years == 1 ? "o" : "i")" }
        if months > 0 { return "\(months) mes\(months == 1 ? "e" : "i")" }
        return "neonato"
    }
}

// MARK: - KBDoctorSpecialization displayName helper

private extension KBDoctorSpecialization {
    var displayName: String {
        switch self {
        case .pediatra:             return "Pediatra"
        case .medicoBase:           return "Medico di base"
        case .dermatologo:          return "Dermatologo"
        case .ortopedico:           return "Ortopedico"
        case .otorinolaringoiatra:  return "Otorinolaringoiatra"
        case .oculista:             return "Oculista"
        case .urologo:              return "Urologo"
        case .cardiologo:           return "Cardiologo"
        case .altro:                return "Specialista"
        }
    }
}
