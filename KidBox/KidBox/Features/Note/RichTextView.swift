
//
//  RichTextView.swift
//  KidBox
//

import SwiftUI
import UIKit

// MARK: - Custom UITextView for key commands + paste

final class RichUITextView: UITextView {
    
    var onTab: ((Bool) -> Void)? // Bool = isShift
    var onPastePlainText: ((String) -> Bool)?
    
    override var keyCommands: [UIKeyCommand]? {
        let tab = UIKeyCommand(
            title: "Indent list",
            action: #selector(handleTab),
            input: "\t",
            modifierFlags: []
        )
        tab.discoverabilityTitle = "Indent list"
        
        let shiftTab = UIKeyCommand(
            title: "Outdent list",
            action: #selector(handleShiftTab),
            input: "\t",
            modifierFlags: [.shift]
        )
        shiftTab.discoverabilityTitle = "Outdent list"
        
        return [tab, shiftTab]
    }
    
    @objc private func handleTab() { onTab?(false) }
    @objc private func handleShiftTab() { onTab?(true) }
    
    override func paste(_ sender: Any?) {
        if let s = UIPasteboard.general.string, !s.isEmpty {
            if onPastePlainText?(s) == true { return }
        }
        super.paste(sender)
    }
}

/// Rich text editor backed by UITextView.
/// Stores content as HTML String.
struct RichTextView: UIViewRepresentable {
    @Binding var html: String
    
    var placeholder: String = ""
    var baseFont: UIFont = .preferredFont(forTextStyle: .body)
    
    func makeUIView(context: Context) -> UITextView {
        let tv = RichUITextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        
        tv.typingAttributes = [
            .font: baseFont,
            .foregroundColor: UIColor.label
        ]
        
        // Tab / Shift+Tab (list nesting)
        tv.onTab = { isShift in
            if isShift {
                RichTextFormatter.outdentList(in: tv)
            } else {
                RichTextFormatter.indentList(in: tv)
            }
        }
        
        // Paste multi-paragraph in list
        tv.onPastePlainText = { pasted in
            context.coordinator.handlePastePlainText(pasted, in: tv)
        }
        
        // Initial content
        if let attr = NSAttributedString.fromHTML(html, fallbackFont: baseFont) {
            tv.attributedText = attr
        } else if !placeholder.isEmpty {
            tv.text = placeholder
            tv.textColor = .secondaryLabel
            tv.font = baseFont
        }
        
        // ✅ Toolbar sopra tastiera (stabile, stile Notes)
        let accessory = RichTextAccessoryView(
            onCommand: { cmd in
                RichTextFormatter.toggle(cmd, in: tv)
            },
            onDismiss: { tv.resignFirstResponder() }
        )
        tv.inputAccessoryView = accessory
        
        // (opzionale) tap recognizer checklist se lo usi
        let tapGR = UITapGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.handleChecklistTap(_:)))
        tapGR.delegate = context.coordinator
        tv.addGestureRecognizer(tapGR)
        
        return tv
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.isProgrammaticUpdate = true
        defer { context.coordinator.isProgrammaticUpdate = false }
        
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
        private var isShowingPlaceholder = false
        
        init(_ parent: RichTextView) { self.parent = parent }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if isShowingPlaceholder {
                isShowingPlaceholder = false
                textView.text = ""
                textView.textColor = .label
                textView.font = parent.baseFont
                textView.typingAttributes = [
                    .font: parent.baseFont,
                    .foregroundColor: UIColor.label
                ]
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !parent.placeholder.isEmpty {
                isShowingPlaceholder = true
                textView.text = parent.placeholder
                textView.textColor = .secondaryLabel
                textView.font = parent.baseFont
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            if isShowingPlaceholder { return }
            parent.html = textView.attributedText.toHTML() ?? ""
        }
        
        // Checklist tap (optional)
        @objc func handleChecklistTap(_ gr: UITapGestureRecognizer) {
            guard let tv = gr.view as? UITextView else { return }
            let pt = gr.location(in: tv)
            if RichTextFormatter.handleChecklistTap(at: pt, in: tv) {
                guard !isShowingPlaceholder else { return }
                parent.html = tv.attributedText.toHTML() ?? ""
            }
        }
        
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        
        // Paste multi-paragraph keeps list
        func handlePastePlainText(_ pasted: String, in tv: UITextView) -> Bool {
            guard !pasted.isEmpty else { return false }
            
            let full = NSMutableAttributedString(attributedString: tv.attributedText)
            let ns = full.string as NSString
            
            let sel = tv.selectedRange
            let fullLen = ns.length
            let loc = max(0, min(sel.location, fullLen))
            let len = max(0, min(sel.length, fullLen - loc))
            let clampedSel = NSRange(location: loc, length: len)
            
            let insertionLoc = clampedSel.location
            let safeIdx = full.length > 0 ? min(max(0, insertionLoc), full.length - 1) : nil
            let currentPS = safeIdx.flatMap { full.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle }
            let isInList = !(currentPS?.textLists ?? []).isEmpty
            
            let font = (tv.typingAttributes[.font] as? UIFont) ?? parent.baseFont
            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label
            ]
            
            full.replaceCharacters(in: clampedSel, with: NSAttributedString(string: pasted, attributes: baseAttrs))
            
            let insertedLen = (pasted as NSString).length
            let insertedRange = NSRange(location: clampedSel.location, length: insertedLen)
            
            if isInList, let ps0 = currentPS {
                let listStyle = (ps0.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                applyToParagraphs(in: full, selection: insertedRange) { pr in
                    full.addAttribute(.paragraphStyle, value: listStyle, range: pr)
                }
                
                var ta = tv.typingAttributes
                ta[.paragraphStyle] = listStyle
                ta[.font] = font
                ta[.foregroundColor] = UIColor.label
                tv.typingAttributes = ta
            }
            
            tv.textStorage.setAttributedString(full)
            tv.selectedRange = NSRange(location: clampedSel.location + insertedLen, length: 0)
            return true
        }
        
        private func applyToParagraphs(in text: NSAttributedString, selection: NSRange, _ block: (NSRange) -> Void) {
            let ns = text.string as NSString
            let fullLen = ns.length
            guard fullLen > 0 else { return }
            
            let loc = max(0, min(selection.location, fullLen))
            let len = max(0, min(selection.length, fullLen - loc))
            let sel = NSRange(location: loc, length: len)
            
            let expanded = ns.paragraphRange(for: sel)
            
            var index = expanded.location
            while index <= expanded.location + expanded.length {
                let pr = ns.paragraphRange(for: NSRange(location: index, length: 0))
                if pr.length == 0 { break }
                block(pr)
                let next = pr.location + pr.length
                if next <= index { break }
                index = next
                if index >= expanded.location + expanded.length { break }
            }
        }
    }
}

// MARK: - HTML conversion helpers

extension NSAttributedString {
    static func fromHTML(_ html: String, fallbackFont: UIFont) -> NSAttributedString? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "", attributes: [.font: fallbackFont, .foregroundColor: UIColor.label])
        }
        
        guard let data = trimmed.data(using: .utf8) else { return nil }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let raw = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        
        // normalize fonts (keep bold/italic traits but force fallback font family/size)
        raw.enumerateAttribute(.font, in: NSRange(location: 0, length: raw.length)) { value, range, _ in
            let current = (value as? UIFont) ?? fallbackFont
            let traits = current.fontDescriptor.symbolicTraits
            var desc = fallbackFont.fontDescriptor
            if let withTraits = desc.withSymbolicTraits(traits) { desc = withTraits }
            let normalized = UIFont(descriptor: desc, size: fallbackFont.pointSize)
            raw.addAttribute(.font, value: normalized, range: range)
        }
        
        raw.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: raw.length))
        return raw
    }
    
    func toHTML() -> String? {
        let range = NSRange(location: 0, length: length)
        let options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let data = try? data(from: range, documentAttributes: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
