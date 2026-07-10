//
//  WalletDocumentExtractor.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Estrazione automatica dei dati principali da una scansione di documento
//  d'identità (a partire dalla Tessera Sanitaria italiana):
//  - Codice Fiscale: quasi sempre presente come barcode Code 39 sul fronte
//    della tessera, con fallback a un pattern regex sul testo OCR.
//  - Data di scadenza: cercata via OCR accanto a etichette tipo
//    "SCADENZA"/"VALIDITA'".
//
//  Stesso framework Vision già usato da `WalletPDFParser` per i barcode dei
//  biglietti, qui applicato a un'immagine scansionata invece che a un PDF.
//

import Foundation
import UIKit
import PDFKit
import Vision

struct WalletDocumentExtraction {
    var codiceFiscale: String?
    var holderName: String?
    var birthInfo: String?
    var documentNumber: String?
    var issueDate: Date?
    var expiryDate: Date?
    /// Solo patente: categorie possedute con rilascio (col.10) e scadenza (col.11)
    /// lette dalla tabella sul retro.
    var patenteCategories: [KBPatenteCategory] = []
    var rawText: String
}

/// Una riga di testo riconosciuta da Vision con il suo riquadro (coordinate
/// normalizzate, origine in basso a sinistra). Serve per leggere le tabelle
/// (es. retro patente) associando le date alla riga/categoria per posizione.
private struct OCRLine {
    let text: String
    let rect: CGRect
}

enum WalletDocumentExtractor {

    private static let codiceFiscalePattern =
        #"[A-Z]{6}[0-9LMNPQRSTUV]{2}[A-EHLMPRT][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]"#

    /// Analizza le pagine scansionate (fronte/retro) ed estrae i dati disponibili.
    /// `kind` abilita euristiche specifiche (es. campi numerati della patente).
    static func extract(from pages: [UIImage], kind: KBWalletDocumentKind = .altro) async -> WalletDocumentExtraction {
        var codiceFiscale: String?
        var fullText = ""
        var patenteCategories: [KBPatenteCategory] = []

        for page in pages {
            guard let cg = page.cgImage else { continue }

            if codiceFiscale == nil, let barcodeCF = detectCodiceFiscaleBarcode(cg) {
                codiceFiscale = barcodeCF
            }

            let lines = recognizeLines(cg)
            let text = lines.map(\.text).joined(separator: "\n")
            if !text.isEmpty {
                fullText += (fullText.isEmpty ? "" : "\n") + text
            }

            // Patente: la tabella con rilascio/scadenza per categoria è sul retro;
            // la pagina che la contiene "vince" (ha date), le altre non ne hanno.
            if kind == .patente {
                let cats = parsePatenteTable(lines: lines)
                if !cats.isEmpty { patenteCategories = cats }
            }
        }

        return extraction(fromText: fullText, barcodeCF: codiceFiscale, kind: kind, patenteCategories: patenteCategories)
    }

    /// Analizza un file già salvato (PDF cifrato→plaintext, o immagine) e ne
    /// estrae i dati. Usato dal flusso "collega documento esistente".
    static func extract(fromFileData data: Data, mimeType: String, kind: KBWalletDocumentKind = .altro) async -> WalletDocumentExtraction {
        let images = renderImages(data: data, mimeType: mimeType)
        return await extract(from: images, kind: kind)
    }

    /// Costruisce l'estrazione a partire dal testo OCR completo (+ eventuale CF
    /// già letto dal barcode). Isolato così è riusabile/testabile.
    private static func extraction(fromText fullText: String, barcodeCF: String?, kind: KBWalletDocumentKind, patenteCategories: [KBPatenteCategory]) -> WalletDocumentExtraction {
        var codiceFiscale = barcodeCF
        if codiceFiscale == nil {
            codiceFiscale = firstMatch(of: codiceFiscalePattern, in: fullText.uppercased())
        }

        // Rileviamo tutte le date del testo con `NSDataDetector` (robusto su molti
        // formati) e le assegniamo per vicinanza alle etichette.
        let dates = detectedDates(in: fullText)

        // Rilascio: solo se accanto a un'etichetta (senza etichetta è rischioso —
        // potrebbe essere la data di nascita).
        var issue = dateNearLabel(labelPattern: issueLabelPattern, dates: dates, in: fullText)
        if issue == nil { issue = monthYearNearLabel(issueLabelPattern, in: fullText) }

        // Scadenza: accanto all'etichetta "SCADENZA/VALIDITÀ"; se manca, fallback
        // alla data futura più lontana ma plausibile (evita la data di nascita).
        var expiry = dateNearLabel(labelPattern: expiryLabelPattern, dates: dates, in: fullText)
        if expiry == nil { expiry = monthYearNearLabel(expiryLabelPattern, in: fullText) }
        if expiry == nil { expiry = plausibleExpiry(from: dates) }

        var holder = extractHolderName(from: fullText)
        var docNumber = extractDocumentNumber(from: fullText)
        var birthInfo: String?
        var categories = patenteCategories

        // Patente (fronte): 1=cognome, 2=nome, 3=nascita, 5=numero, 9=categorie.
        // Le date NON si prendono da 4a/4b/4c: rilascio/scadenza sono per-categoria
        // dalla tabella del retro (`patenteCategories`). Se il retro non è
        // leggibile, usiamo i codici del campo 9 (senza date, da compilare a mano).
        if kind == .patente {
            let p = parsePatente(fullText)
            let name = [p.name, p.surname].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty { holder = name }
            if let num = p.number { docNumber = num }
            birthInfo = p.birthInfo
            issue = nil
            expiry = nil
            codiceFiscale = nil   // la patente non riporta il Codice Fiscale
            if categories.isEmpty, !p.categoryCodes.isEmpty {
                categories = p.categoryCodes.map { KBPatenteCategory(code: $0, issueDate: nil, expiryDate: nil) }
            }
        }

        return WalletDocumentExtraction(
            codiceFiscale: codiceFiscale,
            holderName: holder,
            birthInfo: birthInfo,
            documentNumber: docNumber,
            issueDate: issue,
            expiryDate: expiry,
            patenteCategories: categories,
            rawText: fullText
        )
    }

    /// Cerca un Codice Fiscale in un testo qualsiasi (es. `KBDocument.extractedText`
    /// salvato al momento dell'acquisizione). Usato dalla detail view per rigenerare
    /// il barcode senza dover salvare campi dedicati sul modello `KBDocument`.
    static func codiceFiscale(in text: String) -> String? {
        firstMatch(of: codiceFiscalePattern, in: text.uppercased())
    }

    // MARK: - Rendering (PDF / immagine → [UIImage])

    private static func renderImages(data: Data, mimeType: String) -> [UIImage] {
        if mimeType == "application/pdf" || data.prefix(4) == Data([0x25, 0x50, 0x44, 0x46]) {
            guard let doc = PDFDocument(data: data) else { return [] }
            var images: [UIImage] = []
            for i in 0..<min(doc.pageCount, 4) {
                guard let page = doc.page(at: i) else { continue }
                images.append(page.thumbnail(of: CGSize(width: 2000, height: 2000), for: .cropBox))
            }
            return images
        }
        if let image = UIImage(data: data) {
            return [image]
        }
        return []
    }

    // MARK: - Barcode (Codice Fiscale)

    private static func detectCodiceFiscaleBarcode(_ cg: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.code39, .code39Checksum, .code39FullASCII]
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            for obs in request.results ?? [] {
                guard let payload = obs.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !payload.isEmpty else { continue }
                if firstMatch(of: "^\(codiceFiscalePattern)$", in: payload.uppercased()) != nil {
                    return payload.uppercased()
                }
            }
        } catch {
            KBLog.ui.kbError("[WalletDocumentExtractor] barcode detection failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - OCR

    /// Righe riconosciute con il loro riquadro (per la lettura di tabelle).
    private static func recognizeLines(_ cg: CGImage) -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["it-IT", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            return (request.results ?? []).compactMap { obs in
                guard let s = obs.topCandidates(1).first?.string else { return nil }
                return OCRLine(text: s, rect: obs.boundingBox)
            }
        } catch {
            KBLog.ui.kbError("[WalletDocumentExtractor] OCR failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Patente: tabella retro (col.10 rilascio, col.11 scadenza)

    private static let patenteCategorySet: Set<String> =
        ["AM", "A1", "A2", "A", "B1", "B", "C1", "C", "D1", "D", "BE", "C1E", "CE", "D1E", "DE"]
    private static let patenteCategoryOrder =
        ["AM", "A1", "A2", "A", "B1", "B", "C1", "C", "D1", "D", "BE", "C1E", "CE", "D1E", "DE"]

    /// Legge la tabella sul retro della patente: per ogni riga-categoria associa
    /// le date presenti sulla stessa riga (per posizione verticale). La prima
    /// data (colonna 10) è il rilascio, la seconda (colonna 11) la scadenza.
    /// Vengono restituite solo le categorie che hanno almeno una data (= possedute).
    private static func parsePatenteTable(lines: [OCRLine]) -> [KBPatenteCategory] {
        struct Anchor { let code: String; let y: CGFloat }
        struct DateTok { let date: Date; let y: CGFloat; let x: CGFloat }

        var anchors: [Anchor] = []
        var dateToks: [DateTok] = []

        for line in lines {
            let y = line.rect.midY
            // categoria: token che coincide esattamente con un codice noto
            let tokens = line.text.uppercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            if let code = tokens.first(where: { patenteCategorySet.contains($0) }) {
                anchors.append(Anchor(code: code, y: y))
            }
            // date sulla riga (in ordine di lettura → col.10 poi col.11)
            let dates = licenseDates(in: line.text)
            for (i, d) in dates.enumerated() {
                dateToks.append(DateTok(date: d, y: y, x: line.rect.minX + CGFloat(i) * 0.0001))
            }
        }

        guard !anchors.isEmpty, !dateToks.isEmpty else { return [] }

        // ogni data → categoria con la y più vicina (entro una soglia di riga)
        let threshold: CGFloat = 0.03
        var perCode: [String: [(x: CGFloat, date: Date)]] = [:]
        for dt in dateToks {
            guard let nearest = anchors.min(by: { abs($0.y - dt.y) < abs($1.y - dt.y) }),
                  abs(nearest.y - dt.y) <= threshold else { continue }
            perCode[nearest.code, default: []].append((dt.x, dt.date))
        }

        var result: [KBPatenteCategory] = []
        for code in patenteCategoryOrder {
            guard let dates = perCode[code], !dates.isEmpty else { continue }
            let sorted = dates.sorted { $0.x < $1.x }
            result.append(KBPatenteCategory(
                code: code,
                issueDate: sorted.first?.date,
                expiryDate: sorted.count > 1 ? sorted[1].date : nil
            ))
        }
        return result
    }

    /// Date della patente: gg/mm/aa o gg/mm/aaaa. Anno a 2 cifre: 00–49 → 2000+,
    /// 50–99 → 1900+ (così "34" = 2034, "92" = 1992).
    private static func licenseDates(in text: String) -> [Date] {
        let pattern = #"\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges == 4,
                  let day = Int(ns.substring(with: m.range(at: 1))),
                  let month = Int(ns.substring(with: m.range(at: 2))),
                  var year = Int(ns.substring(with: m.range(at: 3))),
                  (1...31).contains(day), (1...12).contains(month) else { return nil }
            if year < 100 { year += (year <= 49 ? 2000 : 1900) }
            var comps = DateComponents()
            comps.day = day; comps.month = month; comps.year = year
            return calendar.date(from: comps)
        }
    }

    // MARK: - Date (rilascio / scadenza)

    private static let expiryLabelPattern = #"(?i)(scadenza|validit[aà]|expir|valid\s*until|date\s*of\s*expiry)"#
    private static let issueLabelPattern = #"(?i)(rilasci|emission|emess|date\s*of\s*issue|issued)"#
    private static let monthYearPattern = #"\b(\d{1,2})[\/\-. ](\d{4})\b"#

    private struct LocatedDate { let date: Date; let start: Int }

    /// Tutte le date del testo, con la posizione (offset carattere) dove iniziano.
    /// Usa `NSDataDetector`: riconosce gg/mm/aaaa, gg mese aaaa, mesi a parole,
    /// molto più robusto di una regex fatta a mano.
    private static func detectedDates(in text: String) -> [LocatedDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let ns = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let d = m.date else { return nil }
            return LocatedDate(date: d, start: m.range.location)
        }
    }

    /// Posizioni di fine delle etichette che matchano `pattern`.
    private static func labelEndLocations(_ pattern: String, in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { $0.range.location + $0.range.length }
    }

    /// La data che compare *subito dopo* una delle etichette (entro `window`
    /// caratteri): così "SCADENZA 20/03/2029" assegna 20/03/2029 alla scadenza
    /// e non a un altro campo.
    private static func dateNearLabel(labelPattern: String, dates: [LocatedDate], in text: String, window: Int = 40) -> Date? {
        let labels = labelEndLocations(labelPattern, in: text)
        var best: (distance: Int, date: Date)?
        for labelEnd in labels {
            for d in dates {
                let distance = d.start - labelEnd
                guard distance >= -2, distance <= window else { continue }
                if best == nil || distance < best!.distance {
                    best = (distance, d.date)
                }
            }
        }
        return best?.date
    }

    /// Fallback per la scadenza senza etichetta: la data più avanti nel tempo
    /// ma plausibile (da un anno fa a +20 anni), così non prende la data di nascita.
    private static func plausibleExpiry(from dates: [LocatedDate]) -> Date? {
        let now = Date()
        let lower = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        let upper = Calendar.current.date(byAdding: .year, value: 20, to: now) ?? now
        return dates.map(\.date).filter { $0 >= lower && $0 <= upper }.max()
    }

    /// Fallback "mm/aaaa" (solo mese/anno) accanto a un'etichetta: `NSDataDetector`
    /// a volte non lo riconosce come data. Interpretato come primo giorno del mese.
    private static func monthYearNearLabel(_ labelPattern: String, in text: String) -> Date? {
        let lines = text.components(separatedBy: .newlines)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        for (idx, line) in lines.enumerated() {
            guard line.range(of: labelPattern, options: .regularExpression) != nil else { continue }
            let candidates = [line] + (idx + 1 < lines.count ? [lines[idx + 1]] : [])
            for candidate in candidates {
                guard let regex = try? NSRegularExpression(pattern: monthYearPattern) else { continue }
                let ns = candidate as NSString
                guard let m = regex.firstMatch(in: candidate, range: NSRange(location: 0, length: ns.length)),
                      m.numberOfRanges == 3,
                      let month = Int(ns.substring(with: m.range(at: 1))),
                      let year = Int(ns.substring(with: m.range(at: 2))),
                      (1...12).contains(month) else { continue }
                var comps = DateComponents()
                comps.day = 1; comps.month = month; comps.year = year
                if let date = calendar.date(from: comps) { return date }
            }
        }
        return nil
    }

    // MARK: - Patente fronte (numero + nome)

    private struct PatenteFields {
        var surname: String?
        var name: String?
        var birthInfo: String?
        var number: String?
        var categoryCodes: [String] = []
    }

    /// Dal FRONTE della patente legge: 1=cognome, 2=nome, 3=data e luogo di
    /// nascita, 5=numero patente, 9=categorie possedute. Le date NON si leggono
    /// da 4a/4b/4c (sono per-categoria sul retro, gestite da `parsePatenteTable`).
    private static func parsePatente(_ text: String) -> PatenteFields {
        var fields = PatenteFields()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let v = fieldValue(line, prefix: #"^1\s*[\.\)]?\s+"#) {
                fields.surname = cleanNameToken(v) ?? fields.surname
            } else if let v = fieldValue(line, prefix: #"^2\s*[\.\)]?\s+"#) {
                fields.name = cleanNameToken(v) ?? fields.name
            } else if let v = fieldValue(line, prefix: #"^3\s*[\.\)]?\s+"#) {
                let clean = v.trimmingCharacters(in: .whitespaces)
                if clean.count >= 4 { fields.birthInfo = clean }
            } else if let v = fieldValue(line, prefix: #"^5\s*[\.\)]?\s*"#) {
                if let num = firstMatch(of: #"[A-Z0-9]{6,12}"#, in: v.uppercased()),
                   num.rangeOfCharacter(from: .decimalDigits) != nil,
                   num.rangeOfCharacter(from: .letters) != nil {
                    fields.number = num
                }
            } else if let v = fieldValue(line, prefix: #"^9\s*[\.\)]?\s*"#) {
                fields.categoryCodes = parseFrontCategoryCodes(v)
            }
        }
        return fields
    }

    /// "A2 A B" → ["A2","A","B"], tenendo solo i codici categoria validi.
    private static func parseFrontCategoryCodes(_ text: String) -> [String] {
        text.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: " ,;/\t"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { patenteCategorySet.contains($0) }
    }

    /// Se `line` inizia col prefisso regex, restituisce il testo che segue.
    private static func fieldValue(_ line: String, prefix: String) -> String? {
        guard let r = line.range(of: prefix, options: .regularExpression) else { return nil }
        let value = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - Nome / cognome titolare

    /// Euristica label-based: cerca le etichette COGNOME/SURNAME e NOME/GIVEN
    /// NAMES tipiche di Tessera Sanitaria, CIE, Patente, Passaporto, e prende
    /// il valore sulla stessa riga (dopo l'etichetta) o sulla riga successiva.
    /// Best-effort: se non trova nulla resta `nil` (l'utente completa a mano).
    private static func extractHolderName(from text: String) -> String? {
        let surname = valueForLabel(#"(?i)^\s*(cognome|surname)\b"#, in: text)
        let given = valueForLabel(#"(?i)^\s*(nome|given\s*names?)\b"#, in: text, excluding: #"(?i)cognome|surname"#)

        let parts = [given, surname].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    /// Restituisce il valore "pulito" associato a un'etichetta: rimuove
    /// l'etichetta stessa (e le sue varianti bilingue tipo "COGNOME/SURNAME"),
    /// poi prende ciò che resta sulla riga o la riga successiva se vuota.
    private static func valueForLabel(_ labelPattern: String, in text: String, excluding: String? = nil) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            if let excluding, line.range(of: excluding, options: .regularExpression) != nil { continue }
            guard line.range(of: labelPattern, options: .regularExpression) != nil else { continue }

            // rimuovi la parte "etichetta" (parole alfabetiche iniziali + eventuale "/altra lingua")
            let stripped = line.replacingOccurrences(
                of: #"(?i)^\s*(cognome|surname|nome|given\s*names?)[\s/]*(cognome|surname|nome|given\s*names?)?[:\s/]*"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if let clean = cleanNameToken(stripped) { return clean }
            if idx + 1 < lines.count, let clean = cleanNameToken(lines[idx + 1]) { return clean }
        }
        return nil
    }

    /// Accetta solo token plausibili come nome (lettere maiuscole/spazi/apostrofi,
    /// 2–40 char), scartando righe con cifre o troppo corte.
    private static func cleanNameToken(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, t.count <= 40 else { return nil }
        guard t.range(of: #"^[A-Za-zÀ-ÿ' .]+$"#, options: .regularExpression) != nil else { return nil }
        return t
    }

    // MARK: - Numero documento

    /// Cerca il numero del documento accanto a etichette tipo "NUMERO",
    /// "DOCUMENTO N", "CARTA N", "PASSAPORTO N". Prende il primo token
    /// alfanumerico di almeno 5 caratteri che non sia una data.
    private static func extractDocumentNumber(from text: String) -> String? {
        let labelPattern = #"(?i)(numero|document|carta|passaport|n[°.]?\s*documento)"#
        let tokenPattern = #"\b([A-Z0-9]{5,15})\b"#

        let lines = text.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            guard line.range(of: labelPattern, options: .regularExpression) != nil else { continue }
            let candidates = [line] + (idx + 1 < lines.count ? [lines[idx + 1]] : [])
            for candidate in candidates {
                if let token = firstMatch(of: tokenPattern, in: candidate.uppercased()),
                   token.rangeOfCharacter(from: .decimalDigits) != nil,          // deve contenere cifre
                   firstMatch(of: #"^\d{1,2}[\/\-.]\d{1,2}"#, in: token) == nil { // non è una data
                    return token
                }
            }
        }
        return nil
    }

    // MARK: - Regex helper

    private static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        return nsText.substring(with: match.range)
    }
}
