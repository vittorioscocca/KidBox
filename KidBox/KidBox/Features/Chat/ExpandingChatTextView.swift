//
//  ExpandingChatTextView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI
import UIKit

struct ExpandingChatTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    
    let isEnabled: Bool
    let placeholder: String
    let onTextChange: () -> Void
    
    var minHeight: CGFloat = 40
    var maxHeight: CGFloat = 120
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        
        textView.delegate = context.coordinator
        textView.isScrollEnabled = false
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 6, bottom: 9, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = .tertiaryLabel
        } else {
            textView.text = text
            textView.textColor = .label
        }
        
        DispatchQueue.main.async {
            self.recalculateHeight(view: textView)
        }
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        
        let isShowingPlaceholder = textView.textColor == .tertiaryLabel
        
        if text.isEmpty {
            if !isShowingPlaceholder || textView.text != placeholder {
                textView.text = placeholder
                textView.textColor = .tertiaryLabel
            }
        } else {
            if textView.text != text || isShowingPlaceholder {
                textView.text = text
                textView.textColor = .label
            }
        }
        
        Self.recalculateHeightStatic(
            view: textView,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }
    
    private func recalculateHeight(view: UITextView) {
        Self.recalculateHeightStatic(
            view: view,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }
    
    private static func recalculateHeightStatic(
        view: UITextView,
        measuredHeight: Binding<CGFloat>,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) {
        let fittingSize = CGSize(width: view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width, height: .greatestFiniteMagnitude)
        let size = view.sizeThatFits(fittingSize)
        let clamped = min(max(size.height, minHeight), maxHeight)
        
        if measuredHeight.wrappedValue != clamped {
            DispatchQueue.main.async {
                measuredHeight.wrappedValue = clamped
            }
        }
        
        view.isScrollEnabled = size.height > maxHeight
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ExpandingChatTextView
        
        init(_ parent: ExpandingChatTextView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == .tertiaryLabel {
                textView.text = nil
                textView.textColor = .label
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .tertiaryLabel
                parent.text = ""
                parent.onTextChange()
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            if textView.textColor == .tertiaryLabel {
                return
            }
            
            parent.text = textView.text
            parent.onTextChange()
            
            ExpandingChatTextView.recalculateHeightStatic(
                view: textView,
                measuredHeight: parent.$measuredHeight,
                minHeight: parent.minHeight,
                maxHeight: parent.maxHeight
            )
        }
    }
}
