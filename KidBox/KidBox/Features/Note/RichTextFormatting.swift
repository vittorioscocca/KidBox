//
//  RichTextFormatting.swift
//  KidBox
//

import UIKit

// MARK: - Commands

enum RichTextCommand {
    case bold
    case italic
    case underline
    case strikethrough
    case h1
    case h2
    case body
    case bullet
    case number
    case checklist   // ○ circle marker, tappabile
    case quote
    case indentMore
    case indentLess
}

// MARK: - Formatter

final class RichTextFormatter {
    
    static func toggle(_ cmd: RichTextCommand, in tv: UITextView) {
        switch cmd {
        case .bold:          toggleFontTrait(.traitBold, in: tv)
        case .italic:        toggleFontTrait(.traitItalic, in: tv)
        case .underline:     toggleUnderline(in: tv)
        case .strikethrough: toggleStrikethrough(in: tv)
        case .h1:            applyHeader(level: 1, in: tv)
        case .h2:            applyHeader(level: 2, in: tv)
        case .body:          applyBody(in: tv)
        case .bullet:        toggleList(kind: .bullet, in: tv)
        case .number:        toggleList(kind: .numbered, in: tv)
        case .checklist:     toggleList(kind: .checklist, in: tv)
        case .quote:         toggleQuote(in: tv)
        case .indentMore:    changeIndent(delta: +12, in: tv)
        case .indentLess:    changeIndent(delta: -12, in: tv)
        }
    }
    
    // MARK: - Bold / Italic
    
    private static func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, in tv: UITextView) {
        let range = tv.selectedRange
        let base  = UIFont.preferredFont(forTextStyle: .body)
        
        if range.length == 0 {
            // No selection: toggle typing attributes
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
    
    private static func toggledTrait(_ trait: UIFontDescriptor.SymbolicTraits,
                                     in font: UIFont) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let desc = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: desc, size: font.pointSize)
    }
    
    // MARK: - Underline
    
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
        // Check if ALL chars in range already have underline → remove; otherwise add
        let allUnderlined = rangeIsFullyUnderlined(text, range: range)
        let next = allUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        text.addAttribute(.underlineStyle, value: next, range: range)
        apply(text, to: tv, selection: range)
    }
    
    private static func rangeIsFullyUnderlined(_ text: NSAttributedString, range: NSRange) -> Bool {
        var allUnderlined = true
        text.enumerateAttribute(.underlineStyle, in: range) { val, _, stop in
            let v = (val as? Int) ?? 0
            if v == 0 { allUnderlined = false; stop.pointee = true }
        }
        return allUnderlined
    }
    
    // MARK: - Strikethrough
    
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
        let allStruck = rangeIsFullyStrikethrough(text, range: range)
        let next = allStruck ? 0 : NSUnderlineStyle.single.rawValue
        text.addAttribute(.strikethroughStyle, value: next, range: range)
        apply(text, to: tv, selection: range)
    }
    
    private static func rangeIsFullyStrikethrough(_ text: NSAttributedString, range: NSRange) -> Bool {
        var all = true
        text.enumerateAttribute(.strikethroughStyle, in: range) { val, _, stop in
            let v = (val as? Int) ?? 0
            if v == 0 { all = false; stop.pointee = true }
        }
        return all
    }
    
    // MARK: - Headers / Body
    
    private static func applyHeader(level: Int, in tv: UITextView) {
        let size: CGFloat = level == 1 ? 26 : 20
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let range = tv.selectedRange
        if range.length == 0 { tv.typingAttributes[.font] = font; return }
        let text = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in
            text.addAttribute(.font, value: font, range: pr)
        }
        apply(text, to: tv, selection: range)
    }
    
    private static func applyBody(in tv: UITextView) {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let range = tv.selectedRange
        if range.length == 0 { tv.typingAttributes[.font] = font; return }
        let text = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in
            text.addAttribute(.font, value: font, range: pr)
        }
        apply(text, to: tv, selection: range)
    }
    
    // MARK: - Quote
    
    private static func toggleQuote(in tv: UITextView) {
        let range = tv.selectedRange
        let text  = mutableCopy(tv)
        forEachParagraph(in: text, selection: range) { pr in
            let ps    = paragraphStyle(in: text, at: pr.location)
            let isOn  = ps.firstLineHeadIndent >= 16
            ps.firstLineHeadIndent = isOn ? 0 : 16
            ps.headIndent          = isOn ? 0 : 16
            ps.paragraphSpacingBefore = isOn ? 0 : 2
            text.addAttribute(.paragraphStyle, value: ps, range: pr)
        }
        apply(text, to: tv, selection: range)
    }
    
    // MARK: - Indent
    
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
    
    // MARK: - Lists
    
    private enum ListKind {
        case bullet, numbered, checklist
        var markerFormat: NSTextList.MarkerFormat {
            switch self {
            case .bullet:    return .disc     // •
            case .numbered:  return .decimal  // 1. 2. 3.
            case .checklist: return .circle   // ○  (tappabile via tap gesture)
            }
        }
    }
    
    private static func toggleList(kind: ListKind, in tv: UITextView) {
        if kind == .checklist {
            toggleChecklistPrefix(in: tv)
            return
        }
        let sel  = tv.selectedRange
        let ns   = tv.attributedText.string as NSString
        let effective: NSRange = sel.length > 0
        ? sel
        : ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        
        let list   = NSTextList(markerFormat: kind.markerFormat, options: 0)
        let text   = mutableCopy(tv)
        let mfRaw  = kind.markerFormat.rawValue
        let remove = allParagraphsHaveList(text, selection: effective, markerFormat: mfRaw)
        
        forEachParagraph(in: text, selection: effective) { pr in
            let ps = paragraphStyle(in: text, at: pr.location)
            if remove {
                ps.textLists            = []
                ps.headIndent           = 0
                ps.firstLineHeadIndent  = 0
                ps.tabStops             = []
                ps.defaultTabInterval   = 0
            } else {
                ps.textLists            = [list]
                let indent: CGFloat     = 32
                ps.firstLineHeadIndent  = indent
                ps.headIndent           = indent
                ps.tabStops             = [NSTextTab(textAlignment: .left, location: indent)]
                ps.defaultTabInterval   = indent
                ps.paragraphSpacing     = 2
            }
            text.addAttribute(.paragraphStyle, value: ps, range: pr)
        }
        
        tv.textStorage.setAttributedString(text)
        tv.selectedRange = sel.length > 0
        ? sel
        : NSRange(location: effective.location + effective.length, length: 0)
    }
    
    private static func toggleChecklistPrefix(in tv: UITextView) {
        let full = tv.attributedText ?? NSAttributedString()
        let ms = NSMutableAttributedString(attributedString: full)
        
        let sel = tv.selectedRange
        let ns = ms.string as NSString
        let fullLen = ns.length
        if fullLen == 0 { return }
        
        let effective: NSRange = sel.length > 0
        ? NSRange(location: max(0, min(sel.location, fullLen)), length: max(0, min(sel.length, fullLen - max(0, min(sel.location, fullLen)))))
        : ns.paragraphRange(for: NSRange(location: max(0, min(sel.location, fullLen - 1)), length: 0))
        
        // 1) Precompute paragraph ranges ONCE (no mutations while collecting)
        let expanded = ns.paragraphRange(for: effective)
        var paragraphs: [NSRange] = []
        
        var idx = expanded.location
        while idx < expanded.location + expanded.length, idx < fullLen {
            let pr = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            if pr.length == 0 { break }
            paragraphs.append(pr)
            let next = pr.location + pr.length
            if next <= idx { break }
            idx = next
        }
        
        if paragraphs.isEmpty { return }
        
        // 2) Decide if we are removing (allHave) or adding
        var allHave = true
        for pr in paragraphs {
            let line = ns.substring(with: pr).trimmingCharacters(in: .whitespacesAndNewlines)
            if !(line.hasPrefix("○ ") || line.hasPrefix("◉ ")) {
                allHave = false
                break
            }
        }
        
        // 3) Mutate in REVERSE so earlier ranges don't shift
        for prOriginal in paragraphs.reversed() {
            let currentNS = ms.string as NSString
            let curLen = currentNS.length
            if curLen == 0 { break }
            
            // Clamp paragraph range to current length (because ms may have changed)
            let prLoc = max(0, min(prOriginal.location, curLen))
            let prEnd = min(prLoc + prOriginal.length, curLen)
            let prLen = max(0, prEnd - prLoc)
            if prLen == 0 { continue }
            let pr = NSRange(location: prLoc, length: prLen)
            
            var line = currentNS.substring(with: pr)
            let hasNL = line.hasSuffix("\n")
            if hasNL { line.removeLast() }
            
            let lineLen = max(0, pr.length - (hasNL ? 1 : 0))
            if lineLen == 0 { continue }
            let lineRange = NSRange(location: pr.location, length: lineLen)
            
            let str = currentNS.substring(with: lineRange)
            
            // safe paragraphStyle fetch index
            let styleIndex = min(max(0, pr.location), ms.length - 1)
            let ps = (ms.attribute(.paragraphStyle, at: styleIndex, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
            
            if allHave {
                // remove prefix "○ " / "◉ "
                if str.hasPrefix("○ ") || str.hasPrefix("◉ ") {
                    if lineRange.location + 2 <= ms.length {
                        ms.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
                    }
                }
                
                ps.firstLineHeadIndent = 0
                ps.headIndent = 0
                ps.tabStops = []
                ps.defaultTabInterval = 0
                ps.textLists = []
                
                // Apply style (clamped)
                let safePrEnd = min(pr.location + pr.length, ms.length)
                let safePr = NSRange(location: pr.location, length: max(0, safePrEnd - pr.location))
                if safePr.length > 0 {
                    ms.addAttribute(.paragraphStyle, value: ps, range: safePr)
                }
                
                // Clear checked styling (clamped)
                let safeLineEnd = min(lineRange.location + lineRange.length, ms.length)
                let safeLine = NSRange(location: lineRange.location, length: max(0, safeLineEnd - lineRange.location))
                if safeLine.length > 0 {
                    ms.removeAttribute(.strikethroughStyle, range: safeLine)
                    ms.addAttribute(.foregroundColor, value: UIColor.label, range: safeLine)
                }
                
            } else {
                // add prefix if missing
                if !(str.hasPrefix("○ ") || str.hasPrefix("◉ ")) {
                    if lineRange.location <= ms.length {
                        ms.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "○ ")
                    }
                }
                
                // indent to align after circle
                let indent: CGFloat = 28
                ps.firstLineHeadIndent = indent
                ps.headIndent = indent
                ps.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                ps.defaultTabInterval = indent
                ps.textLists = [] // IMPORTANT: not a bullet list
                
                let safePrEnd = min(pr.location + pr.length, ms.length)
                let safePr = NSRange(location: pr.location, length: max(0, safePrEnd - pr.location))
                if safePr.length > 0 {
                    ms.addAttribute(.paragraphStyle, value: ps, range: safePr)
                }
            }
        }
        
        tv.textStorage.setAttributedString(ms)
        tv.selectedRange = sel
    }
    
    private static func allParagraphsHaveList(_ text: NSAttributedString,
                                              selection: NSRange,
                                              markerFormat: String) -> Bool {
        var all = true
        forEachParagraph(in: text, selection: selection) { pr in
            let ps = text.attribute(.paragraphStyle, at: max(0, pr.location),
                                    effectiveRange: nil) as? NSParagraphStyle
            if !(ps?.textLists ?? []).contains(where: { $0.markerFormat.rawValue == markerFormat }) {
                all = false
            }
        }
        return all
    }
    
    // MARK: - Checklist tap: ○ → ◉ (filled circle = "checked")
    
    /// Returns true if a checklist marker was hit and toggled.
    @discardableResult
    static func handleChecklistTap(at point: CGPoint, in tv: UITextView) -> Bool {
        let lm = tv.layoutManager
        let tc = tv.textContainer
        let ins = tv.textContainerInset
        let adj = CGPoint(x: point.x - ins.left, y: point.y - ins.top)
        
        // solo se tap nella colonna marker
        guard adj.x < 28 else { return false }
        
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: adj, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        let full = tv.attributedText ?? NSAttributedString()
        guard full.length > 0, idx < full.length else { return false }
        
        let ns = full.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
        
        var line = ns.substring(with: para)
        if line.hasSuffix("\n") { line.removeLast() }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // IMPORTANT: solo checklist testuale, non liste bullet/numerate
        guard trimmed.hasPrefix("○ ") || trimmed.hasPrefix("◉ ") else { return false }
        
        let ms = NSMutableAttributedString(attributedString: full)
        
        // toggle first char at paragraph start
        let start = para.location
        guard start < ms.length else { return false }
        
        let first = (ms.string as NSString).substring(with: NSRange(location: start, length: 1))
        let willCheck = (first == "○")
        ms.replaceCharacters(in: NSRange(location: start, length: 1), with: willCheck ? "◉" : "○")
        
        // style whole line (no newline)
        let hasNL = ns.substring(with: para).hasSuffix("\n")
        let lineRange = NSRange(location: para.location, length: max(0, para.length - (hasNL ? 1 : 0)))
        if lineRange.length > 0, lineRange.location + lineRange.length <= ms.length {
            if willCheck {
                ms.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
                ms.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: lineRange)
            } else {
                ms.removeAttribute(.strikethroughStyle, range: lineRange)
                ms.addAttribute(.foregroundColor, value: UIColor.label, range: lineRange)
            }
        }
        
        tv.textStorage.setAttributedString(ms)
        return true
    }
    
    // MARK: - List nesting (Tab / Shift+Tab)
    
    static func indentList(in tv: UITextView)  { changeListLevel(delta: +1, in: tv) }
    static func outdentList(in tv: UITextView) { changeListLevel(delta: -1, in: tv) }
    
    private static func changeListLevel(delta: Int, in tv: UITextView) {
        let sel = tv.selectedRange
        let ns  = tv.attributedText.string as NSString
        let eff = sel.length > 0
        ? sel
        : ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        
        let text = mutableCopy(tv)
        forEachParagraph(in: text, selection: eff) { pr in
            let ps = paragraphStyle(in: text, at: pr.location)
            guard !ps.textLists.isEmpty else { return }
            
            if delta > 0 {
                let nested = NSTextList(markerFormat: ps.textLists.last!.markerFormat, options: 0)
                ps.textLists.append(nested)
            } else {
                if ps.textLists.count > 1 { ps.textLists.removeLast() }
                else                      { ps.textLists = [] }
            }
            
            let level  = max(0, ps.textLists.count)
            let indent = level == 0 ? 0 : 32 * CGFloat(level)
            ps.firstLineHeadIndent = indent
            ps.headIndent          = indent
            ps.tabStops  = indent == 0 ? [] : [NSTextTab(textAlignment: .left, location: indent)]
            ps.defaultTabInterval = indent == 0 ? 0 : indent
            text.addAttribute(.paragraphStyle, value: ps, range: pr)
        }
        tv.textStorage.setAttributedString(text)
        tv.selectedRange = sel
    }
    
    // MARK: - Shared paragraph / mutation helpers
    
    static func forEachParagraph(in text: NSAttributedString,
                                 selection: NSRange,
                                 _ block: (NSRange) -> Void) {
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
    
    private static func paragraphStyle(in text: NSAttributedString,
                                       at location: Int) -> NSMutableParagraphStyle {
        guard let ps = text.attribute(.paragraphStyle, at: max(0, location),
                                      effectiveRange: nil) as? NSParagraphStyle
        else { return NSMutableParagraphStyle() }
        return (ps.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    }
    
    private static func mutableCopy(_ tv: UITextView) -> NSMutableAttributedString {
        NSMutableAttributedString(attributedString: tv.attributedText)
    }
    
    private static func apply(_ text: NSMutableAttributedString,
                              to tv: UITextView,
                              selection: NSRange) {
        tv.textStorage.setAttributedString(text)
        tv.selectedRange = selection
    }
}
