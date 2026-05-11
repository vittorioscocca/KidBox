//
//  WalletPDFParser.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import PDFKit
import Vision

struct WalletParsedTicketData {
    let suggestedTitle: String
    let kind: KBWalletTicketKind
    let emitter: String?
    let eventDate: Date?
    let eventEndDate: Date?
    let location: String?
    let bookingCode: String?
    let addToAppleWalletURL: String?
    let barcodeText: String?
    let barcodeFormat: String?
    let notes: String?
}

enum WalletPDFParser {

    static func parse(pdfData: Data, fileName: String?) -> WalletParsedTicketData {
        guard let doc = PDFDocument(data: pdfData) else {
            let fallbackTitle = fallbackTitle(from: fileName)
            return WalletParsedTicketData(
                suggestedTitle: fallbackTitle,
                kind: .other,
                emitter: nil,
                eventDate: nil,
                eventEndDate: nil,
                location: nil,
                bookingCode: nil,
                addToAppleWalletURL: nil,
                barcodeText: nil,
                barcodeFormat: nil,
                notes: nil
            )
        }

        let text = extractText(from: doc)
        let normalized = normalizePdfPlainText(text)
        let detection = WalletEmitterDetector.detect(from: text)
        let (barcodeText, barcodeFormat) = extractBarcode(from: doc)
        let eventDate = pickBestEventDate(from: normalized).map { refineMidnightWithNearbyTime(fullText: normalized, date: $0) }
        let addToWalletURL = extractWalletURL(from: doc, fullText: text)
        let location = extractLocation(from: normalized)
        let suggestedTitle = buildTitle(
            fileName: fileName,
            detection: detection,
            eventDate: eventDate,
            fallbackText: normalized
        )

        return WalletParsedTicketData(
            suggestedTitle: suggestedTitle,
            kind: detection.kind,
            emitter: detection.emitter,
            eventDate: eventDate,
            eventEndDate: nil,
            location: location,
            bookingCode: detection.bookingCode,
            addToAppleWalletURL: addToWalletURL,
            barcodeText: barcodeText,
            barcodeFormat: barcodeFormat,
            notes: extractShortNotes(from: text)
        )
    }

    private static func extractText(from doc: PDFDocument) -> String {
        var chunks: [String] = []
        let maxPages = min(doc.pageCount, 8)
        guard maxPages > 0 else { return "" }

        for idx in 0..<maxPages {
            if let pageText = doc.page(at: idx)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                chunks.append(pageText)
            }
        }
        return chunks.joined(separator: "\n")
    }

    private static func extractBarcode(from doc: PDFDocument) -> (String?, String?) {
        let maxPages = min(doc.pageCount, 3)
        guard maxPages > 0 else { return (nil, nil) }

        for idx in 0..<maxPages {
            guard let page = doc.page(at: idx) else { continue }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 1800), for: .cropBox)
            guard let cg = image.cgImage else { continue }
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                if let obs = request.results?.first as? VNBarcodeObservation,
                   let payload = obs.payloadStringValue, !payload.isEmpty {
                    return (payload, obs.symbology.rawValue)
                }
            } catch {
                continue
            }
        }
        return (nil, nil)
    }

    /// Sceglie la migliore data evento tra i candidati estratti dal testo normalizzato.
    private static func pickBestEventDate(from normalized: String) -> Date? {
        var candidates: [Date] = []
        candidates.append(contentsOf: extractInlineDates(from: normalized))
        candidates.append(contentsOf: extractAdjacentDateAndTime(from: normalized))
        candidates.append(contentsOf: extractLabeledDateTimeLines(from: normalized))
        candidates.append(contentsOf: extractItalianLongMonthDates(from: normalized))
        candidates.append(contentsOf: extractDepartureContextDates(from: normalized))
        let now = Date().addingTimeInterval(-24 * 3600)
        return candidates.filter { $0 >= now }.sorted().first ?? candidates.sorted().first
    }

    /// Se la data è a mezzanotte (solo giorno), cerca un’ora `HH:mm` subito dopo la stessa data nel PDF (traghetti / Moby / ecc.).
    private static func refineMidnightWithNearbyTime(fullText: String, date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        if hour != 0 || minute != 0 { return date }

        let day = cal.component(.day, from: date)
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date)
        guard day > 0, month > 0, year > 0 else { return date }

        let needles: [String] = [
            String(format: "%02d/%02d/%04d", day, month, year),
            String(format: "%d/%d/%04d", day, month, year),
            String(format: "%d/%02d/%04d", day, month, year),
            String(format: "%02d/%d/%04d", day, month, year),
            String(format: "%02d-%02d-%04d", day, month, year),
            String(format: "%d-%d-%04d", day, month, year),
            String(format: "%02d.%02d.%04d", day, month, year),
        ]

        let nsFull = fullText as NSString
        for needle in needles {
            let r = nsFull.range(of: needle)
            guard r.location != NSNotFound else { continue }
            let start = r.location + r.length
            let maxLen = min(900, nsFull.length - start)
            guard maxLen > 0 else { continue }
            let window = nsFull.substring(with: NSRange(location: start, length: maxLen))
            if let hm = bestPlausibleTimeAfterDate(in: window) {
                var dc = cal.dateComponents([.year, .month, .day], from: date)
                dc.hour = hm.h
                dc.minute = hm.m
                dc.second = 0
                if let merged = cal.date(from: dc) { return merged }
            }
        }
        return date
    }

    private struct HourMinute { let h: Int; let m: Int }

    /// Preferisce l’ultima ora non 00:00 in finestra (spesso l’orario di partenza è dopo altri orari commerciali nel PDF).
    private static func bestPlausibleTimeAfterDate(in window: String) -> HourMinute? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|[^\d])([01]?\d|2[0-3])[:.]([0-5]\d)(?!\d)"#,
            options: []
        ) else { return nil }
        let ns = window as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ordered: [HourMinute] = []
        regex.enumerateMatches(in: window, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 2,
                  let hr = Range(match.range(at: 1), in: window),
                  let mr = Range(match.range(at: 2), in: window),
                  let h = Int(window[hr]),
                  let m = Int(window[mr]) else { return }
            ordered.append(HourMinute(h: h, m: m))
        }
        let nonMidnight = ordered.filter { !($0.h == 0 && $0.m == 0) }
        return nonMidnight.last
    }

    /// Es. `30 maggio 2025 ore 22:30`, `30 mag 2025 22.30`.
    private static func extractItalianLongMonthDates(from text: String) -> [Date] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(\d{1,2})\s+(gennaio|febbraio|feb\.?|marzo|mar\.?|aprile|apr\.?|maggio|mag\.?|giugno|giu\.?|luglio|lug\.?|agosto|ago\.?|settembre|set\.?|ottobre|ott\.?|novembre|nov\.?|dicembre|dic\.?|gen\.?)\s+(\d{2,4})(?:\s*(?:alle\s*)?(?:ore\s*)?(\d{1,2})[:.](\d{2}))?"#,
            options: []
        ) else { return [] }
        let monthMap: [String: Int] = [
            "gennaio": 1, "gen": 1, "gen.": 1,
            "febbraio": 2, "feb": 2, "feb.": 2,
            "marzo": 3, "mar": 3, "mar.": 3,
            "aprile": 4, "apr": 4, "apr.": 4,
            "maggio": 5, "mag": 5, "mag.": 5,
            "giugno": 6, "giu": 6, "giu.": 6,
            "luglio": 7, "lug": 7, "lug.": 7,
            "agosto": 8, "ago": 8, "ago.": 8,
            "settembre": 9, "set": 9, "set.": 9,
            "ottobre": 10, "ott": 10, "ott.": 10,
            "novembre": 11, "nov": 11, "nov.": 11,
            "dicembre": 12, "dic": 12, "dic.": 12
        ]
        var out: [Date] = []
        let full = NSRange(location: 0, length: (text as NSString).length)
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 3,
                  let dr = Range(match.range(at: 1), in: text),
                  let mr = Range(match.range(at: 2), in: text),
                  let yr = Range(match.range(at: 3), in: text),
                  let d = Int(text[dr]),
                  let yFull = Int(text[yr]),
                  let mon = monthMap[String(text[mr]).lowercased()] else { return }
            let y = yFull < 100 ? 2000 + yFull : yFull
            var timePart: String?
            if match.numberOfRanges > 4 {
                let r4 = match.range(at: 4)
                let r5 = match.range(at: 5)
                if r4.location != NSNotFound, r5.location != NSNotFound,
                   let hR = Range(r4, in: text), let mR = Range(r5, in: text) {
                    timePart = "\(text[hR]):\(text[mR])"
                }
            }
            let datePart = "\(d)/\(mon)/\(y)"
            if let parsed = parseDate(datePart: datePart, timePart: timePart) {
                out.append(parsed)
            }
        }
        return out
    }

    /// Blocchi «partenza / imbarco / boarding» con data e ora nelle righe vicine (biglietti traghetto).
    private static func extractDepartureContextDates(from text: String) -> [Date] {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var out: [Date] = []
        let kw = ["partenza", "imbarco", "boarding", "departure", "sailing", "navigazione"]
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard kw.contains(where: { lower.contains($0) }) else { continue }
            var chunk = line
            if i + 1 < lines.count { chunk += " " + lines[i + 1] }
            if i + 2 < lines.count { chunk += " " + lines[i + 2] }
            guard let dateRx = try? NSRegularExpression(pattern: #"\b(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})\b"#, options: []) else { continue }
            let ns = chunk as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let dm = dateRx.firstMatch(in: chunk, options: [], range: range),
                  dm.numberOfRanges > 1,
                  let dr = Range(dm.range(at: 1), in: chunk) else { continue }
            let datePart = String(chunk[dr])
            let tailStart = dm.range.location + dm.range.length
            let tailLen = max(0, ns.length - tailStart)
            let tail = tailLen > 0 ? ns.substring(with: NSRange(location: tailStart, length: tailLen)) : ""
            var timePart: String?
            if let tr = try? NSRegularExpression(pattern: #"(?i)(?:alle\s*)?(?:ore\s*)?(\d{1,2})[:.](\d{2})\b"#, options: []),
               let m = tr.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: (tail as NSString).length)),
               m.numberOfRanges > 2,
               let hr = Range(m.range(at: 1), in: tail),
               let mr = Range(m.range(at: 2), in: tail) {
                timePart = "\(tail[hr]):\(tail[mr])"
            }
            if let d = parseDate(datePart: datePart, timePart: timePart) {
                out.append(d)
            }
        }
        return out
    }

    private static func normalizePdfPlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: ",", with: " ")
    }

    private static func extractInlineDates(from text: String) -> [Date] {
        let patterns = [
            #"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})(?:\s+(?:alle\s+)?(?:ore\s*)?(\d{1,2}[:.]\d{2}(?::\d{2})?))?"#,
            #"(\d{4}-\d{2}-\d{2})[T\s]+(\d{1,2}:\d{2}(?::\d{2})?)"#,
            #"(\d{4}-\d{2}-\d{2})(?:\s+(?:alle\s+)?(?:ore\s*)?(\d{1,2}[:.]\d{2}(?::\d{2})?))?"#,
            #"(\d{1,2}\.\d{1,2}\.\d{2,4})(?:\s+(?:alle\s+)?(?:ore\s*)?(\d{1,2}[:.]\d{2}(?::\d{2})?))?"#
        ]
        var out: [Date] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let dateRange = Range(match.range(at: 1), in: text) else { continue }
                let datePart = String(text[dateRange])
                let timePart: String? = {
                    guard match.numberOfRanges > 2 else { return nil }
                    let r = match.range(at: 2)
                    guard r.location != NSNotFound, r.length > 0,
                          let range = Range(r, in: text) else { return nil }
                    return String(text[range])
                }()
                if let parsed = parseDate(datePart: datePart, timePart: timePart) {
                    out.append(parsed)
                }
            }
        }
        return out
    }

    /// Es. "Data\n15/06/2025" + riga "Ora: 14:30" oppure solo data su una riga e ora sulla successiva.
    private static func extractLabeledDateTimeLines(from text: String) -> [Date] {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let dateRx = try? NSRegularExpression(
            pattern: #"(?i)(?:data|date|partenza|departure|viaggio|travel)\s*[:\s.-]+\s*(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})"#,
            options: []
        ) else { return [] }
        guard let timeRx = try? NSRegularExpression(
            pattern: #"(?i)(?:ora|orario|time|hour)\s*[:\s.-]+\s*(\d{1,2})[:.](\d{2})"#,
            options: []
        ) else { return [] }

        var out: [Date] = []
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let dm = dateRx.firstMatch(in: line, options: [], range: range),
                  dm.numberOfRanges > 1,
                  let dr = Range(dm.range(at: 1), in: line) else { continue }
            let datePart = String(line[dr])
            var timePart: String?
            if let tm = timeRx.firstMatch(in: line, options: [], range: range),
               tm.numberOfRanges > 2,
               let hr = Range(tm.range(at: 1), in: line),
               let mr = Range(tm.range(at: 2), in: line) {
                timePart = "\(line[hr]):\(line[mr])"
            } else if i + 1 < lines.count {
                let next = lines[i + 1]
                let nns = next as NSString
                let nr = NSRange(location: 0, length: nns.length)
                if let tm = timeRx.firstMatch(in: next, options: [], range: nr),
                   tm.numberOfRanges > 2,
                   let hr = Range(tm.range(at: 1), in: next),
                   let mr = Range(tm.range(at: 2), in: next) {
                    timePart = "\(next[hr]):\(next[mr])"
                }
            }
            if let d = parseDate(datePart: datePart, timePart: timePart) {
                out.append(d)
            }
        }
        return out
    }

    /// Es. "Partenza 15/06/2025" e riga dopo "14:30" / "Ore 14.30" / "Ora: 14:30".
    private static func extractAdjacentDateAndTime(from text: String) -> [Date] {
        guard let dateToken = try? NSRegularExpression(
            pattern: #"\b(\d{1,2}[/.-]\d{1,2}[/.-]\d{4})\b"#,
            options: []
        ) else { return [] }
        guard let timeLine = try? NSRegularExpression(
            pattern: #"^(?i)(?:ore\s*)?(\d{1,2})[:.](\d{2})\s*$"#,
            options: []
        ) else { return [] }
        guard let labeledTimeLine = try? NSRegularExpression(
            pattern: #"^(?i)(?:ora|orario|time)\s*:\s*(\d{1,2})[:.](\d{2})\s*$"#,
            options: []
        ) else { return [] }
        guard let inlineAfter = try? NSRegularExpression(
            pattern: #"(?i)(?:alle\s+)?(?:ore\s*)?(\d{1,2})[:.](\d{2})\b"#,
            options: []
        ) else { return [] }

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [Date] = []
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            dateToken.enumerateMatches(in: line, options: [], range: full) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let dr = Range(match.range(at: 1), in: line) else { return }
                let datePart = String(line[dr])
                let tail = (match.range.location + match.range.length < ns.length)
                    ? ns.substring(from: match.range.location + match.range.length)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                let combined: String = {
                    if let tr = inlineAfter.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: (tail as NSString).length)),
                       tr.numberOfRanges > 2,
                       let hr = Range(tr.range(at: 1), in: tail),
                       let mr = Range(tr.range(at: 2), in: tail) {
                        return "\(datePart) \(tail[hr]):\(tail[mr])"
                    }
                    if tail.isEmpty || tail.count <= 24,
                       i + 1 < lines.count {
                        let nextLine = lines[i + 1]
                        let nextNs = nextLine as NSString
                        let nextR = NSRange(location: 0, length: nextNs.length)
                        if let tr = timeLine.firstMatch(in: nextLine, options: [], range: nextR),
                           tr.numberOfRanges > 2,
                           let hr = Range(tr.range(at: 1), in: nextLine),
                           let mr = Range(tr.range(at: 2), in: nextLine) {
                            return "\(datePart) \(nextLine[hr]):\(nextLine[mr])"
                        }
                        if let tr = labeledTimeLine.firstMatch(in: nextLine, options: [], range: nextR),
                           tr.numberOfRanges > 2,
                           let hr = Range(tr.range(at: 1), in: nextLine),
                           let mr = Range(tr.range(at: 2), in: nextLine) {
                            return "\(datePart) \(nextLine[hr]):\(nextLine[mr])"
                        }
                    }
                    return datePart
                }()

                if let d = parseCombinedDateTime(combined) {
                    out.append(d)
                }
            }
        }
        return out
    }

    private static func parseDate(datePart: String, timePart: String?) -> Date? {
        let calPart = datePart
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        if let t = timePart?.replacingOccurrences(of: ".", with: ":") {
            return parseCombinedDateTime("\(calPart) \(t)")
        }
        return parseCombinedDateTime(calPart)
    }

    private static func parseCombinedDateTime(_ combinedLine: String) -> Date? {
        let trimmed = combinedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let posix = Locale(identifier: "en_US_POSIX")

        let isoFormats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
        ]
        for format in isoFormats {
            let f = DateFormatter()
            f.locale = posix
            f.calendar = calendar
            f.dateFormat = format
            if let d = f.date(from: trimmed) { return d }
        }

        let normalized = trimmed
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        let hasTime = normalized.range(of: #"\d{1,2}:\d{2}(:\d{2})?"#, options: .regularExpression) != nil
        let timeFormats: [String] = [
            "d/M/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm:ss",
            "d/M/yyyy HH:mm", "d/M/yy HH:mm",
            "dd/MM/yyyy HH:mm", "dd/MM/yy HH:mm",
            "d/M/yyyy HH.mm", "dd/MM/yyyy HH.mm",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd HH.mm",
        ]
        let dateOnlyFormats: [String] = [
            "d/M/yyyy", "d/M/yy", "dd/MM/yyyy", "dd/MM/yy",
            "yyyy/MM/dd",
        ]
        let formats = hasTime ? timeFormats : dateOnlyFormats

        for format in formats {
            for locale in parsingLocales() {
                let f = DateFormatter()
                f.locale = locale
                f.calendar = calendar
                f.dateFormat = format
                if let d = f.date(from: normalized) { return d }
            }
        }
        return nil
    }

    private static func parsingLocales() -> [Locale] {
        // Try system locale first, then keep explicit fallbacks for legacy Italian PDFs.
        [.autoupdatingCurrent, Locale(identifier: "it_IT"), Locale(identifier: "en_US_POSIX")]
    }

    private static func extractWalletURL(from doc: PDFDocument, fullText: String) -> String? {
        let maxPages = min(doc.pageCount, 5)
        for idx in 0..<maxPages {
            guard let page = doc.page(at: idx) else { continue }
            for annotation in page.annotations {
                if let url = annotation.url?.absoluteString,
                   isAppleWalletURL(url) {
                    return url
                }
            }
        }

        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\)"]+"#) else { return nil }
        let matches = regex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText))
        for match in matches {
            guard let range = Range(match.range, in: fullText) else { continue }
            let candidate = String(fullText[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            if isAppleWalletURL(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isAppleWalletURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(".pkpass") || (lower.contains("wallet") && lower.contains("apple"))
    }

    private static func extractLocation(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for line in lines where line.count > 3 {
            let lower = line.lowercased()
            if lower.hasPrefix("da ") || lower.hasPrefix("a ") || lower.contains("stazione") || lower.contains("gate") {
                return line
            }
        }
        return nil
    }

    private static func extractShortNotes(from text: String) -> String? {
        let compact = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "\n")
        return compact.isEmpty ? nil : compact
    }

    private static func buildTitle(
        fileName: String?,
        detection: WalletEmitterDetection,
        eventDate: Date?,
        fallbackText: String
    ) -> String {
        if let emitter = detection.emitter {
            if let eventDate {
                let formatter = DateFormatter()
                formatter.locale = .autoupdatingCurrent
                formatter.dateFormat = "dd MMM"
                return "\(emitter) • \(formatter.string(from: eventDate))"
            }
            return emitter
        }

        let fallback = fallbackTitle(from: fileName)
        if fallback != "Biglietto" { return fallback }

        let firstLine = fallbackText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.count <= 80 })
        return firstLine ?? "Biglietto"
    }

    private static func fallbackTitle(from fileName: String?) -> String {
        guard let fileName, !fileName.isEmpty else { return "Biglietto" }
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? "Biglietto" : base
    }
}
