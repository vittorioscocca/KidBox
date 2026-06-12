//
//  RichTextFormatting.swift
//  KidBox
//

import UIKit
import Combine

// MARK: - Store (bridge RichTextView ↔ toolbar esterna, es. Mac Catalyst)

/// Condiviso tra RichTextView e la toolbar Mac: espone la UITextView e lo stato
/// di formattazione in modo osservabile da SwiftUI.
final class NoteRichTextStore: ObservableObject {
    weak var textView: UITextView?
    let toolbarModel = RichTextToolbarModel()

    func execute(_ cmd: RichTextCommand) {
        guard let tv = textView else { return }
        RichTextFormatter.toggle(cmd, in: tv)
        tv.delegate?.textViewDidChange?(tv)
        NoteRichTextStore.refresh(toolbarModel, from: tv)
    }

    func refreshModel() {
        guard let tv = textView else { return }
        NoteRichTextStore.refresh(toolbarModel, from: tv)
    }

    /// Logica di refresh condivisa (usata anche da RichTextAccessoryView).
    static func refresh(_ model: RichTextToolbarModel, from tv: UITextView) {
        let attr = tv.attributedText ?? NSAttributedString()
        let sel  = tv.selectedRange

        func hasTrait(_ trait: UIFontDescriptor.SymbolicTraits, in range: NSRange) -> Bool {
            guard attr.length > 0 else { return false }
            var has = true
            attr.enumerateAttribute(.font, in: range) { val, _, stop in
                let f = (val as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                if !f.fontDescriptor.symbolicTraits.contains(trait) { has = false; stop.pointee = true }
            }
            return has
        }
        func hasAttr(_ key: NSAttributedString.Key, in range: NSRange) -> Bool {
            guard attr.length > 0 else { return false }
            var has = true
            attr.enumerateAttribute(key, in: range) { val, _, stop in
                if ((val as? Int) ?? 0) == 0 { has = false; stop.pointee = true }
            }
            return has
        }
        func listState(caret: Int) -> RichTextToolbarModel.ActiveList {
            guard attr.length > 0 else { return .none }
            let idx  = max(0, min(caret, attr.length - 1))
            let ns   = attr.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            guard para.length > 0 else { return .none }
            let snip = ns.substring(with: NSRange(location: para.location, length: min(10, para.length)))
            if snip.hasPrefix("○") || snip.hasPrefix("◉")                     { return .checklist }
            if snip.hasPrefix("•")                                              { return .bullet }
            if snip.range(of: #"^\d+\. "#, options: .regularExpression) != nil { return .number }
            return .none
        }

        if sel.length > 0, attr.length > 0 {
            let loc = max(0, min(sel.location, attr.length - 1))
            let len = max(0, min(sel.length, attr.length - loc))
            let range = NSRange(location: loc, length: len)
            model.isBold          = hasTrait(.traitBold,   in: range)
            model.isItalic        = hasTrait(.traitItalic, in: range)
            model.isUnderline     = hasAttr(.underlineStyle,     in: range)
            model.isStrikethrough = hasAttr(.strikethroughStyle, in: range)
            model.activeList      = listState(caret: loc)
        } else {
            let font   = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            let traits = font.fontDescriptor.symbolicTraits
            model.isBold          = traits.contains(.traitBold)
            model.isItalic        = traits.contains(.traitItalic)
            model.isUnderline     = ((tv.typingAttributes[.underlineStyle]     as? Int) ?? 0) != 0
            model.isStrikethrough = ((tv.typingAttributes[.strikethroughStyle] as? Int) ?? 0) != 0
            model.activeList      = listState(caret: max(0, min(sel.location, max(0, attr.length - 1))))
        }
    }
}

// MARK: - Commands

enum RichTextCommand {
    case bold, italic, underline, strikethrough
    case heading        // Intestazione
    case subheading     // Sottointestazione
    case body
    case bullet         // • lista puntata
    case number         // 1. lista numerata
    case checklist      // ○ checklist
    case quote
    case indentMore, indentLess
}

// MARK: - Shared constants

/// Font size dei glifi checklist ○/◉. 26pt per avere cerchi ben visibili
/// (~1.5× il corpo 17pt di default) senza dilatare troppo la line height.
let CHECKLIST_CIRCLE_FONT_SIZE: CGFloat = 26

/// Indent testo della checklist: il cerchio parte dal margine sinistro, il testo
/// (e le righe wrapped) partono da `CHECKLIST_TEXT_INDENT`. Deve essere ≥ larghezza
/// del glifo "○ " a `CHECKLIST_CIRCLE_FONT_SIZE`, altrimenti il testo si sovrappone.
let CHECKLIST_TEXT_INDENT: CGFloat = 34

/// Applica al `NSMutableParagraphStyle` la geometria compatta per una riga
/// checklist: indent del testo wrapped, interlinea 1.0 (così il cerchio grande
/// non dilata la riga) e spacing minimo tra voci consecutive.
func applyChecklistParagraphStyle(_ ps: NSMutableParagraphStyle) {
    let indent = CHECKLIST_TEXT_INDENT
    ps.firstLineHeadIndent = 0
    ps.headIndent          = indent
    ps.tabStops            = [NSTextTab(textAlignment: .left, location: indent)]
    ps.defaultTabInterval  = indent
    // Interlinea compatta: il cerchio ○ è 26pt, se lasciamo
    // `lineHeightMultiple=1.35` (default del body) la riga checklist risulta
    // 26×1.35 ≈ 35pt e le voci della lista appaiono distanti.
    ps.lineHeightMultiple  = 1.0
    ps.paragraphSpacing    = 2
    ps.paragraphSpacingBefore = 0
}

// MARK: - Formatter

final class RichTextFormatter {
    
    static func toggle(_ cmd: RichTextCommand, in tv: UITextView) {
        switch cmd {
        case .bold:          toggleFontTrait(.traitBold,   in: tv)
        case .italic:        toggleFontTrait(.traitItalic, in: tv)
        case .underline:     toggleUnderline(in: tv)
        case .strikethrough: toggleStrikethrough(in: tv)
        case .heading:       applyHeader(level: 1, in: tv)
        case .subheading:    applyHeader(level: 2, in: tv)
        case .body:          applyBody(in: tv)
        case .bullet:        toggleExclusiveList(.bullet, in: tv)
        case .number:        toggleExclusiveList(.number, in: tv)
        case .checklist:     toggleExclusiveList(.checklist, in: tv)
        case .quote:         toggleQuote(in: tv)
        case .indentMore:    changeIndent(delta: +20, in: tv)
        case .indentLess:    changeIndent(delta: -20, in: tv)
        }
    }
    
    // MARK: - Bold / Italic
    
    private static func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, in tv: UITextView) {
        let range = tv.selectedRange
        let base  = UIFont.preferredFont(forTextStyle: .body)
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let font  = (attrs[.font] as? UIFont) ?? base
            attrs[.font] = toggledTrait(trait, in: font)
            tv.typingAttributes = attrs
            return
        }
        let text = mutableCopy(tv)
        text.enumerateAttribute(.font, in: range) { val, sub, _ in
            let font = (val as? UIFont) ?? base
            text.addAttribute(.font, value: toggledTrait(trait, in: font), range: sub)
        }
        apply(text, to: tv, selection: range)
    }
    
    private static func toggledTrait(_ trait: UIFontDescriptor.SymbolicTraits, in font: UIFont) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let desc = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: desc, size: font.pointSize)
    }
    
    // MARK: - Underline / Strikethrough
    
    private static func toggleUnderline(in tv: UITextView) {
        let range = tv.selectedRange
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let cur = (attrs[.underlineStyle] as? Int) ?? 0
            attrs[.underlineStyle] = cur == 0 ? NSUnderlineStyle.single.rawValue : 0
            tv.typingAttributes = attrs
            return
        }
        let text = mutableCopy(tv)
        let allOn = rangeIsFullyStyled(text, range: range, key: .underlineStyle)
        text.addAttribute(.underlineStyle, value: allOn ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        apply(text, to: tv, selection: range)
    }
    
    private static func toggleStrikethrough(in tv: UITextView) {
        let range = tv.selectedRange
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let cur = (attrs[.strikethroughStyle] as? Int) ?? 0
            attrs[.strikethroughStyle] = cur == 0 ? NSUnderlineStyle.single.rawValue : 0
            tv.typingAttributes = attrs
            return
        }
        let text = mutableCopy(tv)
        let allOn = rangeIsFullyStyled(text, range: range, key: .strikethroughStyle)
        text.addAttribute(.strikethroughStyle, value: allOn ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        apply(text, to: tv, selection: range)
    }
    
    private static func rangeIsFullyStyled(_ text: NSAttributedString, range: NSRange,
                                           key: NSAttributedString.Key) -> Bool {
        var all = true
        text.enumerateAttribute(key, in: range) { val, _, stop in
            if ((val as? Int) ?? 0) == 0 { all = false; stop.pointee = true }
        }
        return all
    }
    
    // MARK: - Headers / Body
    
    private static func applyHeader(level: Int, in tv: UITextView) {
        let font = UIFont.systemFont(ofSize: level == 1 ? 26 : 20, weight: .bold)
        let range = tv.selectedRange
        if range.length == 0 { tv.typingAttributes[.font] = font; return }
        let text = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in text.addAttribute(.font, value: font, range: pr) }
        apply(text, to: tv, selection: range)
    }
    
    private static func applyBody(in tv: UITextView) {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let range = tv.selectedRange
        if range.length == 0 { tv.typingAttributes[.font] = font; return }
        let text = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in
            text.addAttribute(.font, value: font, range: pr)
            text.addAttribute(.foregroundColor, value: UIColor.richTextPrimary, range: pr)
        }
        apply(text, to: tv, selection: range)
    }
    
    // MARK: - Quote / Indent
    
    private static func toggleQuote(in tv: UITextView) {
        let range = tv.selectedRange
        let text  = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in
            let ps = paragraphStyle(in: text, at: pr.location)
            let on = ps.firstLineHeadIndent >= 16
            ps.firstLineHeadIndent    = on ? 0 : 16
            ps.headIndent             = on ? 0 : 16
            ps.paragraphSpacingBefore = on ? 0 : 2
            text.addAttribute(.paragraphStyle, value: ps, range: pr)
        }
        apply(text, to: tv, selection: range)
    }
    
    private static func changeIndent(delta: CGFloat, in tv: UITextView) {
        let range = tv.selectedRange
        let text  = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in
            let ps = paragraphStyle(in: text, at: pr.location)
            ps.firstLineHeadIndent = max(0, ps.firstLineHeadIndent + delta)
            ps.headIndent          = max(0, ps.headIndent + delta)
            text.addAttribute(.paragraphStyle, value: ps, range: pr)
        }
        apply(text, to: tv, selection: range)
    }
    
    // MARK: - List indent
    
    static func indentList(in tv: UITextView)  { changeListLevel(delta: +1, in: tv) }
    static func outdentList(in tv: UITextView) { changeListLevel(delta: -1, in: tv) }
    
    private static func changeListLevel(delta: Int, in tv: UITextView) {
        let sel = tv.selectedRange
        let ns  = tv.attributedText.string as NSString
        let eff = sel.length > 0 ? sel : ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        let text = mutableCopy(tv)
        forEachParagraph(in: text, selection: eff) { pr in
            let ps = paragraphStyle(in: text, at: pr.location)
            let step: CGFloat = 20
            ps.firstLineHeadIndent = max(0, ps.firstLineHeadIndent + (delta > 0 ? step : -step))
            ps.headIndent          = max(0, ps.headIndent          + (delta > 0 ? step : -step))
            text.addAttribute(.paragraphStyle, value: ps, range: pr)
        }
        tv.textStorage.setAttributedString(text)
        tv.selectedRange = sel
    }
    
    // MARK: - Exclusive list toggle
    //
    //  Quando si attiva un tipo di lista, i prefissi degli altri due vengono rimossi prima.
    //  Se la riga ha già quel tipo, lo rimuove (toggle off).
    
    private enum ListKind { case bullet, number, checklist }
    
    private static func toggleExclusiveList(_ kind: ListKind, in tv: UITextView) {
        let full = tv.attributedText ?? NSAttributedString()

        // ✅ Fast-path: nota completamente vuota (o placeholder già pulito).
        //    Inserisci subito il marker al caret — come fa Android — così
        //    l'utente vede la lista attivata anche prima di scrivere qualcosa.
        if full.length == 0 {
            insertListMarkerIntoEmptyEditor(tv, kind: kind)
            return
        }

        let ms   = NSMutableAttributedString(attributedString: full)
        let sel  = tv.selectedRange
        let ns   = ms.string as NSString
        let fullLen = ns.length

        // ✅ Se il cursore è su una "riga fantasma" in fondo (es. dopo l'ultimo
        //    `\n`), `paragraphRange` riporterebbe il paragrafo precedente e la
        //    checklist finirebbe lì. Usiamo invece il fast-path che inserisce
        //    il marker al caret, creando una nuova riga lista.
        if sel.length == 0, sel.location == fullLen, fullLen > 0,
           ns.character(at: fullLen - 1) == unichar(("\n" as Character).asciiValue ?? 10) {
            insertListMarkerIntoEmptyEditor(tv, kind: kind)
            return
        }
        
        // Effective range = selection or current paragraph
        let effective: NSRange = {
            if sel.length > 0 {
                let loc = max(0, min(sel.location, fullLen))
                let len = max(0, min(sel.length, fullLen - loc))
                return NSRange(location: loc, length: len)
            } else {
                let loc = max(0, min(sel.location, max(0, fullLen - 1)))
                return ns.paragraphRange(for: NSRange(location: loc, length: 0))
            }
        }()
        
        // Collect paragraph ranges once
        let paragraphs = collectParagraphs(ns: ns, effective: effective, fullLen: fullLen)

        // ✅ Se l'utente è su una riga vuota alla fine del documento (tipico: ha premuto
        //    Return e poi checklist), `paragraphs` può essere vuoto perché il paragrafo
        //    ha length 0. Inseriamo comunque il marker al caret.
        guard !paragraphs.isEmpty else {
            insertListMarkerIntoEmptyEditor(tv, kind: kind)
            return
        }
        
        // Detect current list kind of first paragraph
        let firstLine = ns.substring(with: paragraphs[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let currentKind = detectKind(firstLine)
        
        // If same kind → remove (toggle off). Else → switch to new kind.
        let shouldRemove = (currentKind == kind)
        
        // We mutate in reverse to keep earlier indices stable
        for (i, prOriginal) in paragraphs.reversed().enumerated() {
            let curNS  = ms.string as NSString
            let curLen = curNS.length
            guard curLen >= 0 else { break }
            
            let prLoc = max(0, min(prOriginal.location, max(0, curLen)))
            let prEnd = min(prLoc + prOriginal.length, curLen)
            let prLen = max(0, prEnd - prLoc)
            let pr = NSRange(location: prLoc, length: prLen)
            
            var lineStr = prLen > 0 ? curNS.substring(with: pr) : ""
            let hasNL   = lineStr.hasSuffix("\n")
            if hasNL { lineStr.removeLast() }
            let lineLen = max(0, pr.length - (hasNL ? 1 : 0))
            // ℹ️ Non saltare le righe vuote (lineLen == 0): l'utente vuole
            //     "creare" una checklist anche su una riga vuota — come Android.
            //     Ci limitiamo a non estrarre una sottostringa inesistente.
            let lineRange = NSRange(location: pr.location, length: lineLen)
            let str       = lineLen > 0 ? curNS.substring(with: lineRange) : ""
            
            let styleIdx  = min(max(0, pr.location), ms.length - 1)
            let ps        = mutablePS(ms, at: styleIdx)
            ps.textLists  = []  // sempre: non usiamo NSTextList
            
            // 1) Rimuovi qualunque prefisso esistente (bullet, number, checklist)
            let (stripped, removedLen) = stripListPrefix(str)
            
            if removedLen > 0, lineRange.location + removedLen <= ms.length {
                ms.replaceCharacters(in: NSRange(location: lineRange.location, length: removedLen), with: "")
            }
            
            // 2) Se era checklist, togli anche strikethrough e colori
            let currentLineEnd = min(lineRange.location + lineRange.length, ms.length)
            let currentLineLen = max(0, currentLineEnd - lineRange.location)
            if currentLineLen > 0 {
                let safeRange = NSRange(location: lineRange.location, length: currentLineLen)
                ms.removeAttribute(.strikethroughStyle, range: safeRange)
                ms.addAttribute(.foregroundColor, value: UIColor.richTextPrimary, range: safeRange)
            }
            
            if shouldRemove {
                // Solo rimuovere: azzera indent
                ps.firstLineHeadIndent = 0; ps.headIndent = 0; ps.tabStops = []; ps.defaultTabInterval = 0
            } else {
                // 3) Inserisci nuovo prefisso
                let (newPrefix, prefixAttr) = buildPrefix(kind: kind,
                                                          number: paragraphs.count - i,
                                                          ms: ms,
                                                          at: lineRange.location)
                if let attr = prefixAttr {
                    ms.insert(attr, at: lineRange.location)
                } else if !newPrefix.isEmpty {
                    ms.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: newPrefix)
                }
                
                // 4) Paragraph style per il tipo
                switch kind {
                case .bullet:
                    let indent: CGFloat = 22
                    ps.firstLineHeadIndent = indent; ps.headIndent = indent
                    ps.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                    ps.defaultTabInterval = indent
                    
                case .number:
                    let indent: CGFloat = 30
                    ps.firstLineHeadIndent = indent; ps.headIndent = indent
                    ps.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                    ps.defaultTabInterval = indent
                    
                case .checklist:
                    applyChecklistParagraphStyle(ps)
                }
            }
            
            _ = stripped  // suppress warning
            
            // Applica paragraphStyle
            let newLen  = ms.length
            let pEnd    = min(pr.location + pr.length + (shouldRemove ? 0 : prefixLength(kind: kind, number: paragraphs.count - i)), newLen)
            let safePr  = NSRange(location: pr.location, length: max(0, min(pEnd - pr.location, newLen - pr.location)))
            if safePr.length > 0 { ms.addAttribute(.paragraphStyle, value: ps, range: safePr) }
        }
        
        tv.textStorage.setAttributedString(ms)
        tv.selectedRange = NSRange(location: max(0, min(sel.location, ms.length)), length: 0)
    }
    
    // MARK: - Empty-editor fast path
    //
    // Quando il documento è vuoto (o il paragrafo corrente ha length 0, come
    // succede dopo un Return a fine nota), il flusso normale di
    // `toggleExclusiveList` non ha nulla su cui operare: `collectParagraphs`
    // restituisce `[]` e veniva fuori un no-op. Qui inseriamo direttamente il
    // marker al caret con il paragraphStyle corretto e i typingAttributes
    // giusti per il testo che l'utente digiterà subito dopo.

    private static func insertListMarkerIntoEmptyEditor(_ tv: UITextView, kind: ListKind) {
        let ms  = NSMutableAttributedString(attributedString: tv.attributedText ?? NSAttributedString())
        let sel = tv.selectedRange
        let caret = max(0, min(sel.location, ms.length))

        let ps = NSMutableParagraphStyle()
        switch kind {
        case .bullet:
            let indent: CGFloat = 22
            ps.firstLineHeadIndent = indent
            ps.headIndent          = indent
            ps.tabStops            = [NSTextTab(textAlignment: .left, location: indent)]
            ps.defaultTabInterval  = indent
        case .number:
            let indent: CGFloat = 30
            ps.firstLineHeadIndent = indent
            ps.headIndent          = indent
            ps.tabStops            = [NSTextTab(textAlignment: .left, location: indent)]
            ps.defaultTabInterval  = indent
        case .checklist:
            applyChecklistParagraphStyle(ps)
        }

        let (plain, attributed) = buildPrefix(kind: kind, number: 1, ms: ms, at: caret)

        let insertion: NSAttributedString
        switch kind {
        case .checklist:
            // Il cerchio è il prefisso "○ " come NSAttributedString (font 24pt
            // sul glifo). Il paragraphStyle va applicato sull'intera riga.
            let composed = NSMutableAttributedString()
            if let attr = attributed { composed.append(attr) }
            let lineRange = NSRange(location: 0, length: composed.length)
            if lineRange.length > 0 {
                composed.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            }
            insertion = composed
        case .bullet, .number:
            let baseFont = (tv.typingAttributes[.font] as? UIFont)
                ?? UIFont.preferredFont(forTextStyle: .body)
            insertion = NSAttributedString(string: plain, attributes: [
                .font:            baseFont,
                .foregroundColor: UIColor.richTextPrimary,
                .paragraphStyle:  ps
            ])
        }

        ms.insert(insertion, at: caret)
        tv.textStorage.setAttributedString(ms)
        tv.selectedRange = NSRange(location: caret + insertion.length, length: 0)

        // Typing attributes per il testo che l'utente scriverà adesso:
        //  - font "normale" (non il 24pt del cerchio checklist)
        //  - paragraphStyle corretto per mantenere l'indent wrapped
        //  - colore testo primario
        let bodyFont = (tv.typingAttributes[.font] as? UIFont)
            ?? UIFont.preferredFont(forTextStyle: .body)
        tv.typingAttributes = [
            .font:            bodyFont,
            .foregroundColor: UIColor.richTextPrimary,
            .paragraphStyle:  ps
        ]

        // Forza il delegate a pubblicare lo stato aggiornato (così la toolbar
        // si aggiorna e il binding SwiftUI `html` vede il nuovo contenuto).
        tv.delegate?.textViewDidChange?(tv)
    }

    // MARK: - Checklist tap: ○ → ◉ (tappando il cerchio)
    
    @discardableResult
    static func handleChecklistTap(at point: CGPoint, in tv: UITextView) -> Bool {
        let lm  = tv.layoutManager
        let tc  = tv.textContainer
        let ins = tv.textContainerInset
        let adj = CGPoint(x: point.x - ins.left, y: point.y - ins.top)
        // Salviamo il cursore attuale per ripristinarlo: `setAttributedString`
        // resetta sempre la selezione (tipicamente a 0), e l'utente vede il
        // caret "saltare" accanto al cerchio appena tappato.
        let previousSelection = tv.selectedRange

        // ✅ Pre-filtro veloce: il cerchio non può stare oltre 40pt dal margine sinistro
        guard adj.x < 40 else { return false }
        
        var frac: CGFloat = 0
        let charIdx = lm.characterIndex(for: adj, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        let full = tv.attributedText ?? NSAttributedString()
        guard full.length > 0, charIdx < full.length else { return false }
        
        let ns   = full.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: charIdx, length: 0))
        var line = ns.substring(with: para)
        if line.hasSuffix("\n") { line.removeLast() }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Solo righe checklist
        guard trimmed.hasPrefix("○ ") || trimmed.hasPrefix("◉ ") else { return false }
        
        // ✅ Verifica precisa: calcola il bounding rect del glifo del cerchio
        //    e accetta il tap solo se il punto è dentro quella zona (+ 6pt padding).
        let circleIdx = para.location
        guard circleIdx < full.length else { return false }
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: circleIdx, length: 1),
                                       actualCharacterRange: nil)
        let glyphRect  = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        // Offset dal textContainerInset già sottratto in adj
        let hitRect    = glyphRect.insetBy(dx: -8, dy: -6)
        guard hitRect.contains(adj) else { return false }
        
        let ms    = NSMutableAttributedString(attributedString: full)
        let start = para.location
        guard start < ms.length else { return false }
        
        let firstChar = (ms.string as NSString).substring(with: NSRange(location: start, length: 1))
        let willCheck = (firstChar == "○")
        let newCircle = willCheck ? "◉" : "○"
        
        // Sostituisci il cerchio mantenendo il font grande
        ms.replaceCharacters(in: NSRange(location: start, length: 1), with: newCircle)
        ms.addAttributes([
            .font: UIFont.systemFont(ofSize: CHECKLIST_CIRCLE_FONT_SIZE),
            .foregroundColor: willCheck ? UIColor.systemGreen : UIColor.secondaryLabel
        ], range: NSRange(location: start, length: 1))
        
        // Stile testo del resto della riga (escluso newline)
        let hasNL     = ns.substring(with: para).hasSuffix("\n")
        let lineRange = NSRange(location: para.location,
                                length: max(0, para.length - (hasNL ? 1 : 0)))
        
        if lineRange.length > 0, lineRange.location + lineRange.length <= ms.length {
            // Il cerchio occupa posizione `start`, il testo parte da start+2
            let textStart = min(start + 2, lineRange.location + lineRange.length)
            let textRange = NSRange(location: textStart,
                                    length: max(0, lineRange.location + lineRange.length - textStart))
            
            if willCheck {
                // ✅ Spunta: solo il cerchio diventa verde, il testo resta invariato
                ms.addAttribute(.foregroundColor, value: UIColor.systemGreen,
                                range: NSRange(location: start, length: 1))
            } else {
                // Deseleziona: cerchio torna grigio, testo normale (rimuovi eventuale barrato residuo)
                if textRange.length > 0 {
                    ms.removeAttribute(.strikethroughStyle, range: textRange)
                    ms.addAttribute(.foregroundColor, value: UIColor.richTextPrimary, range: textRange)
                }
                ms.addAttribute(.foregroundColor, value: UIColor.secondaryLabel,
                                range: NSRange(location: start, length: 1))
            }
        }
        
        tv.textStorage.setAttributedString(ms)
        // Ripristina il cursore dove era prima del tap: il tap sul cerchio
        // non deve muovere la selezione né far "lampeggiare" il caret
        // accanto al glifo appena cambiato.
        let clampedLoc = max(0, min(previousSelection.location, ms.length))
        let clampedLen = max(0, min(previousSelection.length, ms.length - clampedLoc))
        tv.selectedRange = NSRange(location: clampedLoc, length: clampedLen)
        return true
    }
    
    // MARK: - Shared paragraph helpers
    
    static func forEachParagraph(in text: NSAttributedString, selection: NSRange, _ block: (NSRange) -> Void) {
        let ns  = text.string as NSString
        let len = ns.length
        guard len > 0 else { return }
        let loc = max(0, min(selection.location, len))
        let lth = max(0, min(selection.length, len - loc))
        let exp = ns.paragraphRange(for: NSRange(location: loc, length: lth))
        var idx = exp.location
        while idx <= exp.location + exp.length {
            let pr = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            if pr.length == 0 { break }
            block(pr)
            let next = pr.location + pr.length
            if next <= idx { break }
            idx = next
            if idx >= exp.location + exp.length { break }
        }
    }
    
    private static func paragraphStyle(in text: NSAttributedString, at location: Int) -> NSMutableParagraphStyle {
        guard let ps = text.attribute(.paragraphStyle, at: max(0, location),
                                      effectiveRange: nil) as? NSParagraphStyle
        else { return NSMutableParagraphStyle() }
        return (ps.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    }
    
    private static func mutableCopy(_ tv: UITextView) -> NSMutableAttributedString {
        NSMutableAttributedString(attributedString: tv.attributedText)
    }
    
    private static func apply(_ text: NSMutableAttributedString, to tv: UITextView, selection: NSRange) {
        tv.textStorage.setAttributedString(text)
        tv.selectedRange = selection
    }
    
    // MARK: - List utility
    
    private static func collectParagraphs(ns: NSString, effective: NSRange, fullLen: Int) -> [NSRange] {
        let expanded = ns.paragraphRange(for: effective)
        var result: [NSRange] = []
        var idx = expanded.location
        while idx < expanded.location + expanded.length, idx < fullLen {
            let pr = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            if pr.length == 0 { break }
            result.append(pr)
            let next = pr.location + pr.length
            if next <= idx { break }
            idx = next
        }
        return result
    }
    
    private static func mutablePS(_ ms: NSMutableAttributedString, at idx: Int) -> NSMutableParagraphStyle {
        guard ms.length > 0 else { return NSMutableParagraphStyle() }
        let safe = min(max(0, idx), ms.length - 1)
        return (ms.attribute(.paragraphStyle, at: safe, effectiveRange: nil) as? NSParagraphStyle)?
            .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
    }
    
    /// Rileva il tipo di lista dalla stringa della riga
    private static func detectKind(_ line: String) -> ListKind? {
        if line.hasPrefix("○ ") || line.hasPrefix("◉ ") { return .checklist }
        if line.hasPrefix("• ")                           { return .bullet }
        if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil { return .number }
        return nil
    }
    
    /// Rimuove qualsiasi prefisso lista e restituisce (stringa pulita, caratteri rimossi)
    private static func stripListPrefix(_ str: String) -> (stripped: String, removedLen: Int) {
        if str.hasPrefix("○ ") || str.hasPrefix("◉ ") {
            return (String(str.dropFirst(2)), 2)
        }
        if str.hasPrefix("• ") {
            return (String(str.dropFirst(2)), 2)
        }
        if let r = str.range(of: #"^\d+\. "#, options: .regularExpression) {
            let count = str.distance(from: str.startIndex, to: r.upperBound)
            return (String(str[r.upperBound...]), count)
        }
        return (str, 0)
    }
    
    /// Restituisce il prefisso da inserire (come NSAttributedString per checklist, String per gli altri)
    private static func buildPrefix(kind: ListKind, number: Int, ms: NSMutableAttributedString, at loc: Int)
    -> (plain: String, attributed: NSAttributedString?) {
        switch kind {
        case .bullet:
            return ("• ", nil)
        case .number:
            return ("\(number). ", nil)
        case .checklist:
            let attr = NSAttributedString(string: "○ ", attributes: [
                .font: UIFont.systemFont(ofSize: CHECKLIST_CIRCLE_FONT_SIZE),
                .foregroundColor: UIColor.secondaryLabel
            ])
            return ("", attr)
        }
    }
    
    /// Lunghezza del prefisso inserito (per calcolo range paragraphStyle)
    private static func prefixLength(kind: ListKind, number: Int) -> Int {
        switch kind {
        case .bullet:    return 2          // "• "
        case .number:    return "\(number). ".count
        case .checklist: return 2          // "○ "
        }
    }
}
