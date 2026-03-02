//
//  RichTextAccessoryView.swift
//  KidBox
//

import UIKit
import SwiftUI
import Combine

final class RichTextToolbarModel: ObservableObject {
    @Published var isExpanded: Bool = false
    
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var isStrikethrough: Bool = false
    
    enum ActiveList: Equatable {
        case none, bullet, number, checklist
    }
    @Published var activeList: ActiveList = .none
}

final class RichTextAccessoryView: UIView {
    
    private weak var textView: UITextView?
    let model = RichTextToolbarModel()
    
    private var host: UIHostingController<NoteLiquidToolbar>?
    private var cancellables = Set<AnyCancellable>()
    
    // Heights (tweakable)
    private let baseHeight: CGFloat = 44
    private let expandedExtra: CGFloat = 80  // total ~148
    
    init(onDismiss: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.systemBackground
        isOpaque = true
        
        let root = NoteLiquidToolbar(
            model: model,
            onCommand: { [weak self] cmd in
                guard let self, let tv = self.textView else { return }
                RichTextFormatter.toggle(cmd, in: tv)
                self.refreshFromTextView()
            },
            onDismiss: onDismiss
        )
        
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.isUserInteractionEnabled = true
        addSubview(host.view)
        
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        self.host = host
        
        // When expanded/collapsed: resize accessory + refresh input views
        model.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.invalidateIntrinsicContentSize()
                self.textView?.reloadInputViews()
            }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: model.isExpanded ? (baseHeight + expandedExtra) : baseHeight)
    }
    
    func attach(to tv: UITextView) {
        self.textView = tv
        refreshFromTextView()
    }
    
    /// Call from textViewDidChange + textViewDidChangeSelection
    func refreshFromTextView() {
        guard let tv = textView else { return }
        
        let attr = tv.attributedText ?? NSAttributedString()
        let sel = tv.selectedRange
        
        // 1) Traits from selection (if any) else typingAttributes
        if sel.length > 0, attr.length > 0 {
            let safeLoc = max(0, min(sel.location, max(0, attr.length - 1)))
            let safeLen = max(0, min(sel.length, attr.length - safeLoc))
            let range = NSRange(location: safeLoc, length: safeLen)
            
            model.isBold = rangeHasFontTrait(attr, range: range, trait: .traitBold)
            model.isItalic = rangeHasFontTrait(attr, range: range, trait: .traitItalic)
            model.isUnderline = rangeHasAttrNonZero(attr, range: range, key: .underlineStyle)
            model.isStrikethrough = rangeHasAttrNonZero(attr, range: range, key: .strikethroughStyle)
            
            model.activeList = listState(attributed: attr, caret: safeLoc)
        } else {
            let font = (tv.typingAttributes[.font] as? UIFont)
            ?? UIFont.preferredFont(forTextStyle: .body)
            
            let traits = font.fontDescriptor.symbolicTraits
            model.isBold = traits.contains(.traitBold)
            model.isItalic = traits.contains(.traitItalic)
            
            model.isUnderline = ((tv.typingAttributes[.underlineStyle] as? Int) ?? 0) != 0
            model.isStrikethrough = ((tv.typingAttributes[.strikethroughStyle] as? Int) ?? 0) != 0
            
            let caret = max(0, min(sel.location, max(0, attr.length - 1)))
            model.activeList = listState(attributed: attr, caret: caret)
        }
    }
    
    // MARK: - Helpers
    
    private func rangeHasFontTrait(_ attr: NSAttributedString, range: NSRange, trait: UIFontDescriptor.SymbolicTraits) -> Bool {
        var has = true
        attr.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            if !font.fontDescriptor.symbolicTraits.contains(trait) {
                has = false
                stop.pointee = true
            }
        }
        return has
    }
    
    private func rangeHasAttrNonZero(_ attr: NSAttributedString, range: NSRange, key: NSAttributedString.Key) -> Bool {
        var has = true
        attr.enumerateAttribute(key, in: range) { value, _, stop in
            let v = (value as? Int) ?? 0
            if v == 0 {
                has = false
                stop.pointee = true
            }
        }
        return has
    }
    
    /// Apple Notes-like detection:
    /// - detects NSTextList markers when present
    /// - ALSO detects leading characters in paragraph ("•", "1.", "○", "◉")
    private func listState(attributed: NSAttributedString, caret: Int) -> RichTextToolbarModel.ActiveList {
        guard attributed.length > 0 else { return .none }
        
        let idx = max(0, min(caret, attributed.length - 1))
        let ns = attributed.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
        
        // leading snippet
        var lead = ns.substring(with: NSRange(location: para.location, length: min(6, max(0, para.length))))
        lead = lead.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if lead.hasPrefix("○") || lead.hasPrefix("◯") || lead.hasPrefix("◉") { return .checklist }
        if lead.hasPrefix("•") { return .bullet }
        if lead.range(of: #"^\d+\."#, options: .regularExpression) != nil { return .number }
        
        // fallback to NSTextList if any
        let ps = attributed.attribute(.paragraphStyle, at: idx, effectiveRange: nil) as? NSParagraphStyle
        if let tl = ps?.textLists.first {
            let marker = tl.marker(forItemNumber: 1)
            if marker.contains("•") { return .bullet }
            if marker.contains("1") { return .number }
            if marker.contains("○") || marker.contains("◉") { return .checklist }
        }
        
        return .none
    }
}
