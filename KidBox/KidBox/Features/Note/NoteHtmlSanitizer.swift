//
//  NoteHtmlSanitizer.swift
//  KidBox
//
//  Sanifica l'HTML prodotto da NSAttributedString.data(..., documentType: .html)
//  in modo che sia leggibile anche dai client Android (HtmlCompat.fromHtml)
//  e dagli altri consumatori cross-platform.
//
//  Motivazione: `NSAttributedString.data(..., .html, ...)` emette un documento
//  HTML completo con blocco `<style>p.p1 { ... } span.s1 { ... }</style>` e
//  `class="pN"` sui paragrafi. `HtmlCompat.fromHtml` di Android non interpreta
//  né `<style>` né le classi CSS, e finisce per mostrare il CSS come testo.
//
//  Sanificazione (stessa logica del sanitizer Android in
//  `data/remote/notes/NoteHtmlSanitizer.kt`):
//    1. estrae `<body>...</body>` se è un documento completo;
//    2. rimuove `<head>`, `<style>`, `<meta>`, `<link>`, `<title>`;
//    3. rimuove gli attributi `class="..."` (e con apostrofi);
//    4. rimuove `<!DOCTYPE ...>`, `<html>` e `</html>` residui.
//
//  Non tocca i tag di base (`<b>`, `<i>`, `<u>`, `<p>`, `<br>`, `<ul>`/`<li>`,
//  `<span style="...">`, link, ecc.) che sono gestiti correttamente anche da
//  `HtmlCompat` e resi uguali al rendering nativo iOS quando rientrano in
//  `NSAttributedString.fromHTML`.
//

import Foundation

enum NoteHtmlSanitizer {

    /// Pulisce un frammento HTML in modo cross-platform e lo restituisce
    /// come fragment senza `<html>/<head>/<style>` né attributi `class="..."`.
    static func sanitizeCrossPlatform(_ html: String) -> String {
        guard !html.isEmpty else { return html }
        var s = html

        // 1) Estrai contenuto di <body>...</body> se presente.
        if let bodyRange = rangeOfMatch(
            in: s,
            pattern: "<body[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ),
           let closingBodyRange = s.range(
            of: "</body>",
            options: [.regularExpression, .caseInsensitive, .backwards]
           ),
           bodyRange.upperBound <= closingBodyRange.lowerBound
        {
            s = String(s[bodyRange.upperBound..<closingBodyRange.lowerBound])
        }

        // 2) Via <head>, <style>, <title>, <meta>, <link>.
        s = s.replacingOccurrences(
            of: "<head[^>]*>[\\s\\S]*?</head>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(
            of: "<title[^>]*>[\\s\\S]*?</title>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(
            of: "<meta[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(
            of: "<link[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 3) Rimuovi gli attributi class="..." (doppi e singoli apici).
        s = s.replacingOccurrences(
            of: "\\s+class\\s*=\\s*\"[^\"]*\"",
            with: "",
            options: [.regularExpression]
        )
        s = s.replacingOccurrences(
            of: "\\s+class\\s*=\\s*'[^']*'",
            with: "",
            options: [.regularExpression]
        )

        // 4) Via <!DOCTYPE ...>, <html>, </html> residui.
        s = s.replacingOccurrences(
            of: "<!doctype[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(
            of: "</?html[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rangeOfMatch(
        in source: String,
        pattern: String,
        options: String.CompareOptions
    ) -> Range<String.Index>? {
        source.range(of: pattern, options: options)
    }

    // MARK: - HTML → testo semplice
    //
    // ⚠️ Volutamente NON usa `NSAttributedString(data:options:)` con
    //    `documentType: .html`: quel parser è basato su WebKit, è vincolato al
    //    main thread (usarlo altrove può bloccare o crashare) e costa decine di
    //    millisecondi per nota. Qui serve solo il testo, quindi basta togliere i
    //    tag — è ~100× più veloce e utilizzabile ovunque.

    /// Testo semplice estratto da un frammento HTML.
    /// - Parameter maxInputLength: tronca l'input prima di elaborarlo (utile per
    ///   le anteprime di lista, dove servono poche decine di caratteri).
    static func plainText(from html: String, maxInputLength: Int = .max) -> String {
        var s = maxInputLength < html.count ? String(html.prefix(maxInputLength)) : html
        guard s.contains("<") || s.contains("&") else { return s }

        s = s.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
                                   with: " ",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<br[^>]*>",
                                   with: "\n",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(p|div|li|tr|h[1-6]|blockquote)\\s*>",
                                   with: "\n",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        // Tag lasciato a metà da un troncamento dell'input.
        s = s.replacingOccurrences(of: "<[^>]*$", with: "", options: .regularExpression)
        return decodeEntities(s)
    }

    /// `true` se l'HTML non contiene alcun testo visibile.
    /// Scansione a singolo passaggio con uscita anticipata: pensata per essere
    /// chiamata a ogni ciclo di rendering di SwiftUI.
    static func isBlank(_ html: String) -> Bool {
        var iterator  = html.unicodeScalars.makeIterator()
        var insideTag = false
        let whitespace = CharacterSet.whitespacesAndNewlines

        while let scalar = iterator.next() {
            if insideTag {
                if scalar == ">" { insideTag = false }
                continue
            }
            switch scalar {
            case "<":
                insideTag = true
            case "&":
                // Entità: solo quelle "vuote" (spazi) non contano come contenuto.
                var entity = ""
                while let next = iterator.next(), next != ";", entity.unicodeScalars.count < 8 {
                    entity.unicodeScalars.append(next)
                }
                switch entity.lowercased() {
                case "nbsp", "#160", "#xa0", "ensp", "emsp", "thinsp": continue
                default: return false
                }
            default:
                if whitespace.contains(scalar) { continue }
                return false
            }
        }
        return true
    }

    private static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var s = input
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'")
        ]
        for (entity, replacement) in named {
            s = s.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        s = decodeNumericEntities(s)
        // Per ultimo, altrimenti "&amp;lt;" verrebbe decodificato due volte.
        return s.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        guard input.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]{1,6});")
        else { return input }

        let ns = input as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor,
                                                 length: match.range.location - cursor))
            let isHex = ns.substring(with: match.range(at: 1)).lowercased() == "x"
            let digits = ns.substring(with: match.range(at: 2))
            if let value = UInt32(digits, radix: isHex ? 16 : 10),
               let scalar = Unicode.Scalar(value) {
                result.unicodeScalars.append(scalar)
            }
            cursor = match.range.location + match.range.length
        }
        guard cursor > 0 else { return input }
        result += ns.substring(from: cursor)
        return result
    }
}
