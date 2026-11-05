//
//  OnDeviceDocumentAnalyzer.swift
//  KidBox
//
//  Prototipo: Document Intelligence sul telefono, con Vision e il modello di
//  Apple Intelligence. Il documento non esce dal dispositivo e non consuma
//  messaggi AI.
//
//  Regola di fondo: nel dubbio si ritorna `nil` e il documento segue la strada
//  di sempre verso Claude. Il modello può sbagliare, quindi date, importi e
//  testi si riscontrano nel testo del documento; la persona non la sceglie il
//  modello ma il confronto coi nomi della famiglia.
//
//  Spento nelle build di rilascio (`isEnabled`). Niente lettura da immagine: il
//  modello di Apple sulle foto inventa dati, si passa sempre dal testo.
//

import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import PDFKit
import Vision

enum OnDeviceDocumentAnalyzer {

    struct Person {
        let id: String
        let name: String
    }

    private static let enabledKey = "kb_docintel_ondevice"
    /// Sotto questa soglia il testo letto non basta a dire che documento è.
    private static let minTextLength = 80
    /// Il modello ha 4.096 token in tutto, risposta compresa.
    private static let maxTextLength = 6000
    private static let maxPages = 3

    /// Acceso in Debug, spento in Release. Si cambia con la chiave in UserDefaults.
    static var isEnabled: Bool {
        if let stored = UserDefaults.standard.object(forKey: enabledKey) as? Bool { return stored }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Analisi

    /// Ritorna il risultato per la scheda di conferma, oppure `nil` se il
    /// documento deve andare a Claude.
    static func analyze(pages: [Data], pdfData: Data?, persons: [Person]) async -> DocIntelResult? {
        guard isEnabled else { return nil }
        guard case .available = SystemLanguageModel.default.availability else {
            KBLog.ai.kbInfo("DocIntel on-device: modello non disponibile")
            return nil
        }

        let text = await readableText(pages: pages, pdfData: pdfData)
        guard text.count >= minTextLength, text.count <= maxTextLength else {
            KBLog.ai.kbInfo("DocIntel on-device: testo fuori misura chars=\(text.count)")
            return nil
        }

        do {
            var kind = try await respond(
                to: text, instructions: classifyInstructions, generating: DocKind.self
            )
            // Il modello prende le analisi per referti: i valori con
            // l'intervallo di riferimento invece non lasciano dubbi.
            if kind == .medicalReport, DocumentGrounding.referenceRangeCount(in: text) >= 2 {
                kind = .labResults
            }
            let result = try await extract(kind: kind, text: text, persons: persons)
            KBLog.ai.kbInfo("DocIntel on-device: kind=\(kind.rawValue) risultato=\(result != nil)")
            return result
        } catch {
            // Rifiuto dei filtri, contesto superato, modello occupato.
            KBLog.ai.kbInfo("DocIntel on-device: ripiego su Claude \(error.localizedDescription)")
            return nil
        }
    }

    private static func extract(kind: DocKind, text: String, persons: [Person]) async throws -> DocIntelResult? {
        switch kind {
        case .bill:
            let bill = try await respond(to: text, instructions: instructions(for: "the utility bill"), generating: BillFields.self)
            return billResult(bill, text: text)
        case .receipt:
            let receipt = try await respond(to: text, instructions: instructions(for: "the purchase receipt"), generating: ReceiptFields.self)
            return receiptResult(receipt, text: text)
        case .labResults:
            let lab = try await respond(to: text, instructions: instructions(for: "the laboratory results"), generating: LabFields.self)
            return labResult(lab, text: text, persons: persons)
        case .medicalReport:
            let visit = try await respond(to: text, instructions: instructions(for: "the medical visit report"), generating: VisitFields.self)
            return visitResult(visit, text: text, persons: persons)
        case .prescription, .vehicle, .school, .insurance, .payslip, .other:
            // Azioni più ricche di quelle che si riscontrano qui: restano a Claude.
            return nil
        }
    }

    private static func respond<T: Generable>(
        to text: String, instructions: String, generating type: T.Type
    ) async throws -> T {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(
            to: "Document:\n\(text)",
            generating: type,
            options: GenerationOptions(temperature: 0)
        ).content
    }

    private static var classifyInstructions: String {
        """
        You classify documents of a family. They can be in Italian, English, French or Spanish.
        bill: utility bill still to be paid by a due date (electricity, gas, water, internet, phone).
        receipt: proof of a purchase already paid in a shop or pharmacy, with a total and no due date.
        labResults: list of laboratory values of a patient with reference ranges, such as blood tests.
        medicalReport: report written by a doctor after a visit, with findings or a diagnosis.
        prescription: medicines prescribed, with no visit report.
        vehicle: car tax, service or inspection.
        insurance: insurance policy.
        school: school communication.
        payslip: salary statement.
        other: anything else.
        """
    }

    private static func instructions(for subject: String) -> String {
        """
        You read \(subject) of a family. The document can be in Italian, English, French or Spanish.
        Today is \(isoDay(Date())). Dates in the document are written day first (dd/mm/yyyy).
        Extract the fields in the language of the document. Copy names and values exactly.
        Never invent anything: leave a field empty if the document does not contain it.
        """
    }

    // MARK: - Testo

    private static func readableText(pages: [Data], pdfData: Data?) async -> String {
        if let pdfData, let pdf = PDFDocument(data: pdfData) {
            let native = (0..<min(pdf.pageCount, maxPages))
                .compactMap { pdf.page(at: $0)?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if native.count >= minTextLength { return native }
        }
        // Vision lavora in modo sincrono: fuori dal main thread.
        return await Task.detached(priority: .userInitiated) {
            pages.compactMap { recognizedText(in: $0) }.joined(separator: "\n")
        }.value
    }

    private nonisolated static func recognizedText(in jpeg: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["it-IT", "en-US", "fr-FR", "es-ES"]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Da campi letti a scheda (solo se il testo li conferma)

    static func billResult(_ bill: BillFields, text: String) -> DocIntelResult? {
        guard let subtype = bill.utility.subtype,
              DocumentGrounding.containsAmount(bill.total, in: text),
              DocumentGrounding.isDueDate(bill.dueDate, in: text),
              DocumentGrounding.isGrounded(bill.supplier, in: text) else { return nil }
        var action = DocIntelAction(type: "house_payment")
        action.paymentType = "bolletta"
        action.subtype = subtype
        action.title = bill.supplier
        action.provider = bill.supplier
        action.amount = bill.total
        action.date = bill.dueDate
        return result(category: "bill", title: bill.supplier, action: action)
    }

    static func receiptResult(_ receipt: ReceiptFields, text: String) -> DocIntelResult? {
        guard DocumentGrounding.containsAmount(receipt.total, in: text),
              DocumentGrounding.containsDate(receipt.date, in: text),
              DocumentGrounding.isGrounded(receipt.shop, in: text) else { return nil }
        var action = DocIntelAction(type: "expense_add")
        action.title = receipt.shop
        action.amount = receipt.total
        action.date = receipt.date
        return result(category: "receipt", title: receipt.shop, action: action)
    }

    static func labResult(_ lab: LabFields, text: String, persons: [Person]) -> DocIntelResult? {
        let values = lab.values
        guard !values.isEmpty,
              values.count >= DocumentGrounding.referenceRangeCount(in: text),
              values.allSatisfy({ DocumentGrounding.isGrounded($0.name, in: text) && DocumentGrounding.contains($0.value, in: text) }),
              DocumentGrounding.containsDate(lab.date, in: text),
              DocumentGrounding.isGrounded(lab.title, in: text) else { return nil }
        var action = DocIntelAction(type: "exam_add")
        action.title = lab.title
        action.date = lab.date
        action.childId = DocumentGrounding.personId(in: text, persons: persons)
        action.resultText = values.map(\.line).joined(separator: "\n")
        return result(category: "lab_results", title: lab.title, action: action)
    }

    static func visitResult(_ visit: VisitFields, text: String, persons: [Person]) -> DocIntelResult? {
        // Farmaci, esami e controlli diventano schede a parte: quelle le fa Claude.
        guard !visit.prescribesMedicines, !visit.requestsExams, !visit.schedulesFollowUp,
              DocumentGrounding.containsDate(visit.date, in: text),
              DocumentGrounding.isGrounded(visit.reason, in: text),
              DocumentGrounding.isGrounded(visit.diagnosis, in: text),
              visit.recommendations.isEmpty || DocumentGrounding.isGrounded(visit.recommendations, in: text),
              visit.doctor.isEmpty || DocumentGrounding.isGrounded(visit.doctor, in: text) else { return nil }
        var action = DocIntelAction(type: "medical_visit")
        action.title = visit.reason
        action.date = visit.date
        action.diagnosis = visit.diagnosis
        action.recommendations = visit.recommendations.isEmpty ? nil : visit.recommendations
        action.doctorName = visit.doctor.isEmpty ? nil : visit.doctor
        action.childId = DocumentGrounding.personId(in: text, persons: persons)
        return result(category: "medical_report", title: visit.reason, action: action)
    }

    private static func result(category: String, title: String, action: DocIntelAction) -> DocIntelResult {
        DocIntelResult(documentType: nil, category: category, suggestedTitle: title, actions: [action], onDevice: true)
    }

    private static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Campi letti dal modello

@Generable
enum DocKind: String {
    case bill, receipt, labResults, medicalReport, prescription, vehicle, insurance, school, payslip, other
}

@Generable
enum UtilityKind: String {
    case electricity, gas, water, internet, phone, condominium, other

    /// `nil` = tasse, affitto, mutuo e simili: li smista Claude.
    var subtype: String? {
        switch self {
        case .electricity: return "luce"
        case .gas:         return "gas"
        case .water:       return "acqua"
        case .internet:    return "internet"
        case .phone:       return "telefono"
        case .condominium: return "condominio"
        case .other:       return nil
        }
    }
}

@Generable
struct BillFields {
    @Guide(description: "Company that issued the bill")
    var supplier: String
    var utility: UtilityKind
    @Guide(description: "Total to pay")
    var total: Double
    @Guide(description: "Payment due date as yyyy-MM-dd, not the invoice date")
    var dueDate: String
}

@Generable
struct ReceiptFields {
    @Guide(description: "Name of the shop")
    var shop: String
    @Guide(description: "Total paid")
    var total: Double
    @Guide(description: "Purchase date as yyyy-MM-dd")
    var date: String
}

@Generable
struct LabValue {
    @Guide(description: "Name of the test")
    var name: String
    @Guide(description: "Value as written")
    var value: String
    @Guide(description: "Unit of measure")
    var unit: String
    @Guide(description: "Reference range as written, empty if missing")
    var range: String
    @Guide(description: "True if the value is outside the reference range or marked with an asterisk")
    var outOfRange: Bool

    var line: String {
        var s = "\(name): \(value)"
        // Il modello a volte lascia l'unità anche dentro il valore.
        if !unit.isEmpty, !value.contains(unit) { s += " \(unit)" }
        if !range.isEmpty { s += " (\(range))" }
        if outOfRange { s += " *" }
        return s
    }
}

@Generable
struct LabFields {
    @Guide(description: "Short name of the exam, as written in the document")
    var title: String
    @Guide(description: "Sampling date as yyyy-MM-dd")
    var date: String
    @Guide(description: "Every value in the document", .maximumCount(30))
    var values: [LabValue]
}

@Generable
struct VisitFields {
    @Guide(description: "Reason for the visit, as written")
    var reason: String
    @Guide(description: "Doctor's name, empty if missing")
    var doctor: String
    @Guide(description: "Visit date as yyyy-MM-dd, not the birth date")
    var date: String
    @Guide(description: "Diagnosis or findings, as written")
    var diagnosis: String
    @Guide(description: "Doctor's instructions, as written, empty if missing")
    var recommendations: String
    @Guide(description: "True if the doctor prescribes any medicine")
    var prescribesMedicines: Bool
    @Guide(description: "True if the doctor requests further exams")
    var requestsExams: Bool
    @Guide(description: "True if the doctor asks for a follow-up visit or check")
    var schedulesFollowUp: Bool
}

// MARK: - Riscontro nel testo

/// Controlli senza modello: quello che il modello ha letto deve stare nel documento.
enum DocumentGrounding {

    /// La stringa, a parte maiuscole e accenti, compare nel testo.
    static func contains(_ needle: String, in text: String) -> Bool {
        let n = folded(needle)
        return !n.isEmpty && folded(text).contains(n)
    }

    /// Almeno il 70% delle parole di 4+ lettere compare nel testo: il modello
    /// può ripulire una frase, non aggiungere fatti. Una frase senza parole
    /// lunghe deve comparire intera.
    static func isGrounded(_ phrase: String, in text: String) -> Bool {
        let words = wordList(phrase).filter { $0.count >= 4 }
        guard !words.isEmpty else { return contains(phrase, in: text) }
        let known = Set(wordList(text))
        let found = words.filter { known.contains($0) }.count
        return Double(found) / Double(words.count) >= 0.7
    }

    /// L'importo compare fra i numeri del testo, scritto in qualunque formato.
    static func containsAmount(_ amount: Double, in text: String) -> Bool {
        guard amount > 0 else { return false }
        return numbers(in: text).contains { abs($0 - amount) < 0.005 }
    }

    /// La data ISO compare nel testo: giorno prima del mese, o già ISO. Una data
    /// scritta col mese davanti non torna, e il documento va a Claude.
    static func containsDate(_ iso: String, in text: String) -> Bool {
        guard let date = parseISO(iso) else { return false }
        return dates(in: text).contains(date)
    }

    /// Una bolletta ha almeno due date (emissione e scadenza) e la scadenza è
    /// l'ultima. Scarta anche lo scontrino preso per bolletta, che ne ha una sola.
    static func isDueDate(_ iso: String, in text: String) -> Bool {
        guard let date = parseISO(iso) else { return false }
        let all = Set(dates(in: text))
        return all.count >= 2 && all.max() == date
    }

    /// Righe con un intervallo di riferimento: tante quante i valori da leggere.
    static func referenceRangeCount(in text: String) -> Int {
        matches(
            of: #"(?<![\d/.\-–])\d+(?:[.,]\d+)?\s*[-–]\s*\d+(?:[.,]\d+)?\s*\)?\s*\*?\s*$"#,
            in: text, multiline: true
        ).count
    }

    /// Il solo membro della famiglia il cui nome compare nel testo. Se sono
    /// zero o più di uno decide l'utente nella scheda.
    static func personId(in text: String, persons: [OnDeviceDocumentAnalyzer.Person]) -> String? {
        let known = Set(wordList(text))
        let found = persons.filter { person in
            let parts = wordList(person.name)
            return !parts.isEmpty && parts.allSatisfy { known.contains($0) }
        }
        return found.count == 1 ? found[0].id : nil
    }

    // MARK: - Interni

    private static func folded(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func wordList(_ s: String) -> [String] {
        folded(s).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    private static func matches(of pattern: String, in text: String, multiline: Bool = false) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: multiline ? [.anchorsMatchLines] : []) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map {
                let range = match.range(at: $0)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }

    /// 1.799,26 · 1,799.26 · 1 799,26 · 13.30 · 412: l'ultimo separatore seguito
    /// da due cifre è quello dei decimali.
    private static func numbers(in text: String) -> [Double] {
        matches(of: #"\d[\d\s.,]*\d|\d"#, in: text.replacingOccurrences(of: "\u{00A0}", with: " ")).compactMap { groups in
            var token = groups[0].filter { !$0.isWhitespace }
            var decimals = ""
            if let last = token.lastIndex(where: { $0 == "," || $0 == "." }),
               token.distance(from: last, to: token.endIndex) == 3 {
                decimals = String(token[token.index(after: last)...])
                token = String(token[..<last])
            }
            token.removeAll { $0 == "," || $0 == "." }
            return Double(decimals.isEmpty ? token : "\(token).\(decimals)")
        }
    }

    private static func dates(in text: String) -> [DateComponentsKey] {
        var out = matches(of: #"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b"#, in: text).compactMap { g -> DateComponentsKey? in
            guard let day = Int(g[1]), let month = Int(g[2]), var year = Int(g[3]) else { return nil }
            if year < 100 { year += 2000 }
            return DateComponentsKey(year: year, month: month, day: day).validated
        }
        out += matches(of: #"\b(\d{4})-(\d{2})-(\d{2})\b"#, in: text).compactMap { g -> DateComponentsKey? in
            guard let year = Int(g[1]), let month = Int(g[2]), let day = Int(g[3]) else { return nil }
            return DateComponentsKey(year: year, month: month, day: day).validated
        }
        return out
    }

    private static func parseISO(_ iso: String) -> DateComponentsKey? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard iso.count == 10, parts.count == 3 else { return nil }
        return DateComponentsKey(year: parts[0], month: parts[1], day: parts[2]).validated
    }

    private struct DateComponentsKey: Hashable, Comparable {
        let year: Int, month: Int, day: Int

        var validated: DateComponentsKey? {
            (1...12).contains(month) && (1...31).contains(day) ? self : nil
        }

        static func < (a: Self, b: Self) -> Bool {
            (a.year, a.month, a.day) < (b.year, b.month, b.day)
        }
    }
}
