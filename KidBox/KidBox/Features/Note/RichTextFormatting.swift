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
        let lm  = tv.layoutManager
        let tc  = tv.textContainer
        let ins = tv.textContainerInset
        let adj = CGPoint(x: point.x - ins.left, y: point.y - ins.top)
        
        var frac: CGFloat = 0
        let charIdx = lm.characterIndex(for: adj, in: tc,
                                        fractionOfDistanceBetweenInsertionPoints: &frac)
        let fullLen = tv.attributedText.length
        guard charIdx < fullLen else { return false }
        
        let ns        = tv.attributedText.string as NSString
        let paraRange = ns.paragraphRange(for: NSRange(location: charIdx, length: 0))
        
        guard let ps   = tv.attributedText.attribute(.paragraphStyle,
                                                     at: paraRange.location,
                                                     effectiveRange: nil) as? NSParagraphStyle,
              let item = ps.textLists.first,
              item.markerFormat == .circle || item.markerFormat == .disc
        else { return false }
        
        // Only react if tap is inside marker area
        guard adj.x < ps.headIndent + 10 else { return false }
        
        let isChecked = (item.markerFormat == .disc)   // disc = filled = "checked"
        let newFormat: NSTextList.MarkerFormat = isChecked ? .circle : .disc
        let newList  = NSTextList(markerFormat: newFormat, options: 0)
        
        let newPS    = (ps.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        if !newPS.textLists.isEmpty { newPS.textLists[newPS.textLists.count - 1] = newList }
        
        let text = mutableCopy(tv)
        text.addAttribute(.paragraphStyle, value: newPS, range: paraRange)
        
        // Visual feedback: strikethrough + gray when checked
        let textRange = NSRange(
            location: paraRange.location,
            length: paraRange.length - (ns.substring(with: paraRange).hasSuffix("\n") ? 1 : 0)
        )
        if !isChecked {
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            text.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: textRange)
        } else {
            text.removeAttribute(.strikethroughStyle, range: textRange)
            text.addAttribute(.foregroundColor, value: UIColor.label, range: textRange)
        }
        
        tv.textStorage.setAttributedString(text)
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
