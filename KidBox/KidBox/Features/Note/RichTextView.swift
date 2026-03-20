//
//  RichTextView.swift
//  KidBox
//

import SwiftUI
import UIKit

// MARK: - Custom UITextView

final class RichUITextView: UITextView {
    var onTab: ((Bool) -> Void)?
    var onPastePlainText: ((String) -> Bool)?
    
    override var keyCommands: [UIKeyCommand]? {
        let tab = UIKeyCommand(title: "Indent", action: #selector(handleTab),
                               input: "\t", modifierFlags: [])
        let shiftTab = UIKeyCommand(title: "Outdent", action: #selector(handleShiftTab),
                                    input: "\t", modifierFlags: [.shift])
        return [tab, shiftTab]
    }
    @objc private func handleTab()      { onTab?(false) }
    @objc private func handleShiftTab() { onTab?(true) }
    
    override func paste(_ sender: Any?) {
        if let s = UIPasteboard.general.string, !s.isEmpty,
           onPastePlainText?(s) == true { return }
        super.paste(sender)
    }
}

// MARK: - RichTextView

struct RichTextView: UIViewRepresentable {
    @Binding var html: String
    var placeholder: String  = ""
    var baseFont: UIFont     = .preferredFont(forTextStyle: .body)
    var focusTrigger: UUID?  = nil   // cambia valore per richiedere il focus
    
    func makeUIView(context: Context) -> UITextView {
        let tv = RichUITextView()
        tv.isEditable    = true
        tv.isSelectable  = true
        tv.alwaysBounceVertical = true
        tv.backgroundColor      = .clear
        tv.delegate             = context.coordinator
        tv.textContainerInset   = UIEdgeInsets(top: 2, left: 6, bottom: 10, right: 6)
        tv.typingAttributes     = NSAttributedString.defaultTypingAttributes(font: baseFont)
        
        tv.onTab = { isShift in
            if isShift { RichTextFormatter.outdentList(in: tv) }
            else        { RichTextFormatter.indentList(in: tv) }
        }
        tv.onPastePlainText = { pasted in
            context.coordinator.handlePastePlainText(pasted, in: tv)
        }
        
        if let attr = NSAttributedString.fromHTML(html, fallbackFont: baseFont) {
            tv.attributedText = attr
        } else if !placeholder.isEmpty {
            tv.text      = placeholder
            tv.textColor = .secondaryLabel
            tv.font      = baseFont
        }
        
        // ✅ Accessory view: NON usare translatesAutoresizingMaskIntoConstraints=false
        let accessory = RichTextAccessoryView(onDismiss: {
            // Prima chiudi il pannello espanso (se aperto), poi abbassa la tastiera
            (tv.inputAccessoryView as? RichTextAccessoryView)?.model.isExpanded = false
            tv.resignFirstResponder()
        })
        tv.inputAccessoryView = accessory
        
        let tapGR = UITapGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.handleChecklistTap(_:)))
        tapGR.delegate = context.coordinator
        tv.addGestureRecognizer(tapGR)
        accessory.attach(to: tv)
        
        return tv
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.isProgrammaticUpdate = true
        defer { context.coordinator.isProgrammaticUpdate = false }
        
        // Focus richiesto dal titolo (tasto Avanti)
        if let trigger = focusTrigger, trigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = trigger
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }
        
        let currentHTML = uiView.attributedText.toHTML() ?? ""
        guard currentHTML != html else { return }
        if let attr = NSAttributedString.fromHTML(html, fallbackFont: baseFont) {
            uiView.attributedText = attr
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let parent: RichTextView
        var isProgrammaticUpdate = false
        var lastFocusTrigger: UUID? = nil
        private var isShowingPlaceholder = false
        
        init(_ parent: RichTextView) { self.parent = parent }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            guard isShowingPlaceholder else { return }
            isShowingPlaceholder = false
            textView.text = ""
            textView.textColor = .richTextPrimary
            textView.font = parent.baseFont
            textView.typingAttributes = NSAttributedString.defaultTypingAttributes(font: parent.baseFont)
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !parent.placeholder.isEmpty {
                isShowingPlaceholder = true
                textView.text      = parent.placeholder
                textView.textColor = .secondaryLabel
                textView.font      = parent.baseFont
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate, !isShowingPlaceholder else { return }
            parent.html = textView.attributedText.toHTML() ?? ""
            (textView.inputAccessoryView as? RichTextAccessoryView)?.refreshFromTextView()
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            (textView.inputAccessoryView as? RichTextAccessoryView)?.refreshFromTextView()
        }
        
        // MARK: Checklist tap
        
        @objc func handleChecklistTap(_ gr: UITapGestureRecognizer) {
            guard let tv = gr.view as? UITextView else { return }
            if RichTextFormatter.handleChecklistTap(at: gr.location(in: tv), in: tv) {
                parent.html = tv.attributedText.toHTML() ?? ""
                (tv.inputAccessoryView as? RichTextAccessoryView)?.refreshFromTextView()
            }
        }
        
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        
        // MARK: - shouldChangeText: auto-continue + exit list on Return/Backspace
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n"         { return handleReturn(textView, range: range) }
            if text.isEmpty, range.length == 1 { return handleBackspace(textView, range: range) }
            return true
        }
        
        private func handleReturn(_ tv: UITextView, range: NSRange) -> Bool {
            let full = tv.attributedText ?? NSAttributedString()
            let ns   = full.string as NSString
            let loc  = max(0, min(range.location, ns.length))
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            var line = ns.substring(with: para)
            if line.hasSuffix("\n") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // --- Checklist ---
            if trimmed.hasPrefix("○ ") || trimmed.hasPrefix("◉ ") {
                let content = trimmed.hasPrefix("○ ") ? String(trimmed.dropFirst(2)) : String(trimmed.dropFirst(2))
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    clearCurrentLine(tv, paraRange: para); return false
                }
                insertAttributedContinuation(tv, prefix: NSAttributedString(string: "○ ", attributes: [
                    .font: UIFont.systemFont(ofSize: 20),
                    .foregroundColor: UIColor.secondaryLabel
                ]), paragraphRange: para)
                return false
            }
            
            // --- Bullet ---
            if trimmed.hasPrefix("• ") {
                let content = String(trimmed.dropFirst(2))
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    clearCurrentLine(tv, paraRange: para); return false
                }
                insertPlainContinuation(tv, prefix: "• ", paragraphRange: para)
                return false
            }
            
            // --- Numerato ---
            if let r = trimmed.range(of: #"^(\d+)\. "#, options: .regularExpression) {
                let numStr = String(trimmed[r]).components(separatedBy: ".").first ?? "1"
                let curNum = Int(numStr) ?? 1
                let content = String(trimmed[r.upperBound...])
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    clearCurrentLine(tv, paraRange: para); return false
                }
                insertPlainContinuation(tv, prefix: "\(curNum + 1). ", paragraphRange: para)
                return false
            }
            
            return true
        }
        
        private func handleBackspace(_ tv: UITextView, range: NSRange) -> Bool {
            let full = tv.attributedText ?? NSAttributedString()
            let ns   = full.string as NSString
            let loc  = max(0, min(range.location, ns.length))
            let para = ns.paragraphRange(for: NSRange(location: max(0, loc - 1), length: 0))
            var line = ns.substring(with: para)
            if line.hasSuffix("\n") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Riga vuota con solo marker → esci dalla lista
            let isEmptyChecklist = trimmed == "○" || trimmed == "◉" || trimmed == "○ " || trimmed == "◉ "
            let isEmptyBullet    = trimmed == "•" || trimmed == "• "
            let isEmptyNumber    = trimmed.range(of: #"^\d+\. ?$"#, options: .regularExpression) != nil
            
            if isEmptyChecklist || isEmptyBullet || isEmptyNumber {
                clearCurrentLine(tv, paraRange: para)
                return false
            }
            return true
        }
        
        /// Rimuove il contenuto della riga corrente (marker incluso) e azzera l'indent
        private func clearCurrentLine(_ tv: UITextView, paraRange: NSRange) {
            let ms  = NSMutableAttributedString(attributedString: tv.attributedText)
            let ns  = ms.string as NSString
            let len = ns.length
            let prLoc = max(0, min(paraRange.location, len))
            var line  = ns.substring(with: paraRange)
            let hasNL = line.hasSuffix("\n")
            if hasNL { line.removeLast() }
            let lineLen = max(0, paraRange.length - (hasNL ? 1 : 0))
            if lineLen > 0, prLoc + lineLen <= ms.length {
                ms.replaceCharacters(in: NSRange(location: prLoc, length: lineLen), with: "")
            }
            // Azzera paragraph style
            let ps = NSMutableParagraphStyle()
            let newLen = ms.length
            let newPara = (ms.string as NSString).paragraphRange(for: NSRange(location: min(prLoc, max(0, newLen - 1)), length: 0))
            if newPara.length > 0, newPara.location + newPara.length <= newLen {
                ms.addAttribute(.paragraphStyle, value: ps, range: newPara)
            }
            tv.textStorage.setAttributedString(ms)
            tv.selectedRange = NSRange(location: min(prLoc, ms.length), length: 0)
        }
        
        /// Inserisce "\n" + prefix testuale, copiando il paragraphStyle della riga corrente
        private func insertPlainContinuation(_ tv: UITextView, prefix: String, paragraphRange: NSRange) {
            let full     = tv.attributedText ?? NSAttributedString()
            let styleIdx = max(0, min(paragraphRange.location, max(0, full.length - 1)))
            let ps       = (full.length > 0
                            ? (full.attribute(.paragraphStyle, at: styleIdx, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle
                            : nil) ?? NSMutableParagraphStyle()
            
            let font = (tv.typingAttributes[.font] as? UIFont) ?? parent.baseFont
            let insertion = NSAttributedString(string: "\n" + prefix, attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: ps
            ])
            insertAtCaret(tv, attributed: insertion)
        }
        
        /// Inserisce "\n" + prefix come NSAttributedString (usato per il cerchio grande della checklist)
        private func insertAttributedContinuation(_ tv: UITextView,
                                                  prefix: NSAttributedString,
                                                  paragraphRange: NSRange) {
            let full     = tv.attributedText ?? NSAttributedString()
            let styleIdx = max(0, min(paragraphRange.location, max(0, full.length - 1)))
            let ps       = (full.length > 0
                            ? (full.attribute(.paragraphStyle, at: styleIdx, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle
                            : nil) ?? NSMutableParagraphStyle()
            
            let font = (tv.typingAttributes[.font] as? UIFont) ?? parent.baseFont
            let nl   = NSAttributedString(string: "\n", attributes: [
                .font: font, .foregroundColor: UIColor.label, .paragraphStyle: ps
            ])
            let insertion = NSMutableAttributedString(attributedString: nl)
            insertion.append(prefix)
            
            // Body text part will use normal font on next keystroke
            insertAtCaret(tv, attributed: insertion)
        }
        
        private func insertAtCaret(_ tv: UITextView, attributed: NSAttributedString) {
            let ms  = NSMutableAttributedString(attributedString: tv.attributedText)
            let sel = tv.selectedRange
            let ns  = ms.string as NSString
            let loc = max(0, min(sel.location, ns.length))
            let len = max(0, min(sel.length, ns.length - loc))
            ms.replaceCharacters(in: NSRange(location: loc, length: len), with: attributed)
            tv.textStorage.setAttributedString(ms)
            let newCaret = loc + attributed.length
            tv.selectedRange = NSRange(location: min(newCaret, ms.length), length: 0)
        }
        
        // MARK: - Paste
        
        func handlePastePlainText(_ pasted: String, in tv: UITextView) -> Bool {
            guard !pasted.isEmpty else { return false }
            let ms   = NSMutableAttributedString(attributedString: tv.attributedText)
            let sel  = tv.selectedRange
            let len  = ms.length
            let loc  = max(0, min(sel.location, len))
            let slen = max(0, min(sel.length, len - loc))
            let font = (tv.typingAttributes[.font] as? UIFont) ?? parent.baseFont
            
            // Recupera paragraphStyle del punto di inserimento (mantiene indent ecc.)
            let psAtCaret: NSParagraphStyle
            if len > 0 {
                let idx = max(0, min(loc, len - 1))
                psAtCaret = (ms.attribute(.paragraphStyle, at: idx, effectiveRange: nil)
                             as? NSParagraphStyle) ?? NSMutableParagraphStyle.editorDefault()
            } else {
                psAtCaret = NSMutableParagraphStyle.editorDefault()
            }
            
            // Costruisci attributed string del testo incollato con stile coerente
            let pasteAttr = NSAttributedString(string: pasted, attributes: [
                .font:            font,
                .foregroundColor: UIColor.richTextPrimary,
                .paragraphStyle:  psAtCaret
            ])
            ms.replaceCharacters(in: NSRange(location: loc, length: slen), with: pasteAttr)
            tv.textStorage.setAttributedString(ms)
            tv.selectedRange = NSRange(location: loc + (pasted as NSString).length, length: 0)
            return true
        }
    }
}

// MARK: - Colore testo standard (leggermente meno nero di .label)
//
// UIColor.label = #000000 in light mode — troppo duro.
// Usiamo un grigio scuro con ~88% opacità che si adatta a dark mode.
extension UIColor {
    static var richTextPrimary: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.92, alpha: 1)   // dark: quasi bianco morbido
            : UIColor(white: 0.10, alpha: 1)   // light: antracite (non nero puro)
        }
    }
}

// MARK: - Paragraph style di default per l'editor
//
// Interlinea e spaziatura applicati globalmente al testo del corpo.
extension NSMutableParagraphStyle {
    static func editorDefault() -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple  = 1.35   // respiro verticale tra le righe
        ps.paragraphSpacing    = 4      // piccolo gap tra paragrafi
        ps.lineBreakMode       = .byWordWrapping
        return ps
    }
}

// MARK: - HTML helpers

extension NSAttributedString {
    /// Converte HTML in NSAttributedString preservando bold/italic/size originali
    /// ma normalizzando il font-family al sistema e imponendo colore e interlinea coerenti.
    static func fromHTML(_ html: String, fallbackFont: UIFont) -> NSAttributedString? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "",
                                      attributes: defaultTypingAttributes(font: fallbackFont))
        }
        
        // Inietta CSS che normalizza font, colore, interlinea prima del parse
        let styled = """
        <html><head><meta charset="UTF-8">
        <style>
          body, p, li, td, div, span {
            font-family: -apple-system, sans-serif;
            font-size: \(Int(fallbackFont.pointSize))px;
            color: #1A1A1A;
            line-height: 1.45;
          }
          h1 { font-size: \(Int(fallbackFont.pointSize * 1.9))px; font-weight: bold; }
          h2 { font-size: \(Int(fallbackFont.pointSize * 1.45))px; font-weight: bold; }
          h3 { font-size: \(Int(fallbackFont.pointSize * 1.2))px; font-weight: 600; }
        </style>
        </head><body>\(trimmed)</body></html>
        """
        
        guard let data = styled.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let raw = try? NSMutableAttributedString(data: data,
                                                       options: options,
                                                       documentAttributes: nil)
        else { return nil }
        
        let fullRange = NSRange(location: 0, length: raw.length)
        
        // 1) Normalizza font: mantieni size e traits (bold/italic) dall'HTML,
        //    ma forza il font-family di sistema.
        raw.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let parsed  = (value as? UIFont) ?? fallbackFont
            let traits  = parsed.fontDescriptor.symbolicTraits
            let size    = parsed.pointSize   // rispetta h1/h2/h3 etc.
            var desc    = UIFont.systemFont(ofSize: size).fontDescriptor
            if let t    = desc.withSymbolicTraits(traits) { desc = t }
            raw.addAttribute(.font, value: UIFont(descriptor: desc, size: size), range: range)
        }
        
        // 2) Colore testo uniforme, leggermente più morbido del nero puro
        raw.addAttribute(.foregroundColor, value: UIColor.richTextPrimary, range: fullRange)
        
        // 3) Migliora il paragraphStyle: aumenta interlinea e spaziatura
        //    preservando indent (liste), alignment e altri attributi già presenti.
        raw.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle()
            let ps       = (existing.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
            // Solo se non c'è già un'interlinea significativa (es. dall'HTML)
            if ps.lineHeightMultiple < 1.1 {
                ps.lineHeightMultiple = 1.35
            }
            if ps.paragraphSpacing < 1 {
                ps.paragraphSpacing = 4
            }
            raw.addAttribute(.paragraphStyle, value: ps, range: range)
        }
        
        // 4) Paragrafi senza .paragraphStyle esplicito (testo piatto) → applica default
        raw.enumerateAttribute(.paragraphStyle, in: fullRange,
                               options: .longestEffectiveRangeNotRequired) { value, range, _ in
            if value == nil {
                raw.addAttribute(.paragraphStyle, value: NSMutableParagraphStyle.editorDefault(),
                                 range: range)
            }
        }
        
        return raw
    }
    
    // MARK: - Typing attributes di default per la UITextView
    
    static func defaultTypingAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        [
            .font:            font,
            .foregroundColor: UIColor.richTextPrimary,
            .paragraphStyle:  NSMutableParagraphStyle.editorDefault()
        ]
    }
    
    func toHTML() -> String? {
        let options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let data = try? data(from: NSRange(location: 0, length: length),
                                   documentAttributes: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
