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
}
