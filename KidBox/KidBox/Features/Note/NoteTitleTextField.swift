//
//  NoteTitleTextField.swift
//  KidBox
//

import SwiftUI
import UIKit

struct NoteTitleTextField: UIViewRepresentable {
    
    @Binding var text: String
    var placeholder: String = "Titolo"
    var onReturn: (() -> Void)? = nil
    
    static let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
    
    func makeUIView(context: Context) -> TitleTextView {
        let tv = TitleTextView()
        tv.delegate           = context.coordinator
        tv.font               = Self.titleFont
        tv.textColor          = .label
        tv.backgroundColor    = .clear
        tv.isScrollEnabled    = false
        tv.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.returnKeyType      = .next
        tv.typingAttributes   = [
            .font: Self.titleFont,
            .foregroundColor: UIColor.label
        ]
        // Disabilita auto-insets da SwiftUI
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        
        context.coordinator.updatePlaceholder(tv, text: text, placeholder: placeholder)
        
        let coordinator = context.coordinator
        tv.onReturn = { coordinator.parent.onReturn?() }
        
        return tv
    }
    
    func updateUIView(_ uiView: TitleTextView, context: Context) {
        context.coordinator.isProgrammatic = true
        defer { context.coordinator.isProgrammatic = false }
        
        if context.coordinator.isShowingPlaceholder {
            if !text.isEmpty {
                context.coordinator.isShowingPlaceholder = false
                uiView.text      = text
                uiView.textColor = .label
                uiView.font      = Self.titleFont
            }
        } else {
            if uiView.text != text {
                uiView.text = text
            }
        }
    }
    
    // ✅ Dice a SwiftUI l'altezza esatta in base al contenuto
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TitleTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 32
        let size  = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTitleTextField
        var isProgrammatic       = false
        var isShowingPlaceholder = false
        
        init(_ parent: NoteTitleTextField) { self.parent = parent }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if isShowingPlaceholder {
                isShowingPlaceholder = false
                textView.text      = ""
                textView.textColor = .label
                textView.font      = NoteTitleTextField.titleFont
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            updatePlaceholder(textView, text: parent.text, placeholder: parent.placeholder)
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammatic, !isShowingPlaceholder else { return }
            parent.text = textView.text ?? ""
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n" { parent.onReturn?(); return false }
            return true
        }
        
        func updatePlaceholder(_ tv: UITextView, text: String, placeholder: String) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isShowingPlaceholder = true
                tv.text      = placeholder
                tv.textColor = .placeholderText
                tv.font      = NoteTitleTextField.titleFont
            } else {
                isShowingPlaceholder = false
                tv.text      = text
                tv.textColor = .label
                tv.font      = NoteTitleTextField.titleFont
            }
        }
    }
}

// MARK: - TitleTextView

final class TitleTextView: UITextView {
    var onReturn: (() -> Void)?
    
    override var inputAccessoryView: UIView? {
        get { nil }
        set { }
    }
    
    // Altezza intrinseca stretta al contenuto
    override var intrinsicContentSize: CGSize {
        let size = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : 300,
                                       height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
}
