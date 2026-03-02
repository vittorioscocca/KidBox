//
//  SelectableTextView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.backgroundColor = .clear
        return tv
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.isProgrammaticUpdate = true
        defer { context.coordinator.isProgrammaticUpdate = false }
        
        // 1) sync text -> UITextView
        if uiView.text != text {
            uiView.text = text
        }
        
        // 2) sync selection -> UITextView (clamp)
        let len = (uiView.text as NSString).length
        let loc = max(0, min(selectedRange.location, len))
        let l = max(0, min(selectedRange.length, len - loc))
        let clamped = NSRange(location: loc, length: l)
        
        if uiView.selectedRange != clamped {
            uiView.selectedRange = clamped
        }
        
        // ❌ NON fare: selectedRange = clamped (causa warning)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextView
        var isProgrammaticUpdate = false
        
        init(_ parent: SelectableTextView) { self.parent = parent }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            parent.text = textView.text ?? ""
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            parent.selectedRange = textView.selectedRange
        }
    }
}
