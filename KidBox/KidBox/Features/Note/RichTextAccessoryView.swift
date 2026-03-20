//
//  RichTextAccessoryView.swift
//  KidBox
//

import UIKit
import SwiftUI
import Combine

// MARK: - RichTextToolbarModel

final class RichTextToolbarModel: ObservableObject {
    @Published var isExpanded: Bool      = false
    @Published var isBold: Bool          = false
    @Published var isItalic: Bool        = false
    @Published var isUnderline: Bool     = false
    @Published var isStrikethrough: Bool = false
    
    enum ActiveList: Equatable { case none, bullet, number, checklist }
    @Published var activeList: ActiveList = .none
}

// MARK: - RichTextAccessoryView

// ✅ Strategia definitiva "liquid":
//    Usiamo UIToolbar come contenitore — è esattamente il componente che iOS
//    usa internamente per le inputAccessoryView native (inclusa quella di Safari,
//    Mail, Note). UIToolbar conosce il colore e il materiale della tastiera
//    dall'interno della gerarchia e si fonde senza alcuna linea di separazione.
//    L'altezza è 0 nel frame iniziale: UIToolbar si dimensiona via auto-layout.
final class RichTextAccessoryView: UIToolbar {
    
    private weak var textView: UITextView?
    let model = RichTextToolbarModel()
    
    private var barHost: UIHostingController<NoteLiquidBarView>?
    private var panelContainer: UIView?
    private var panelHost: UIHostingController<NoteLiquidPanelView>?
    private var cancellables = Set<AnyCancellable>()
    
    // Aggiornato da notifica UIKeyboard
    private var keyboardFrameInWindow: CGRect = .zero
    
    private let panelHeight: CGFloat = 118
    private let panelMargin: CGFloat = 8
    
    // MARK: - Init
    
    init(onDismiss: @escaping () -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        autoresizingMask = [.flexibleWidth]
        
        // UIToolbar usa automaticamente il materiale translucente della tastiera.
        // barStyle .default + isTranslucent true = stesso blur della QuickType bar.
        // NON azzerare setBackgroundImage/setShadowImage: si perderebbe il materiale.
        barStyle      = .default
        isTranslucent = true
        // Rimuove solo l'ombra superiore (la reimpostiamo noi con 0.33pt precisi)
        setShadowImage(UIImage(), forToolbarPosition: .any)
        
        // Separatore superiore sottilissimo
        let sep = UIView()
        sep.backgroundColor  = UIColor.separator.withAlphaComponent(0.4)
        sep.autoresizingMask = [.flexibleWidth]
        sep.frame            = CGRect(x: 0, y: 0, width: bounds.width, height: 0.33)
        addSubview(sep)
        
        // ── SwiftUI content ──────────────────────────────────────────────
        let barView = NoteLiquidBarView(
            model: model,
            onCommand: { [weak self] cmd in
                guard let self, let tv = self.textView else { return }
                RichTextFormatter.toggle(cmd, in: tv)
                self.refreshFromTextView()
            },
            onDismiss: onDismiss
        )
        let barHost = UIHostingController(rootView: barView)
        barHost.view.backgroundColor  = .clear
        barHost.view.isOpaque         = false
        barHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        barHost.view.frame            = bounds
        addSubview(barHost.view)
        self.barHost = barHost
        
        // Ascolta notifiche tastiera per avere il frame corretto
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardDidShow(_:)),
            name: UIResponder.keyboardDidShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        
        // Espandi/collassa pannello
        model.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                if expanded { self?.showPanel() } else { self?.hidePanel() }
            }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }
    
    // MARK: - Keyboard notifications
    
    @objc private func keyboardDidShow(_ n: Notification) {
        if let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            keyboardFrameInWindow = frame
        }
    }
    
    @objc private func keyboardWillChangeFrame(_ n: Notification) {
        if let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            keyboardFrameInWindow = frame
            // Se il pannello è visibile, riposizionalo
            if let container = panelContainer, let window = keyWindow() {
                let yTop = keyboardTopY(in: window)
                UIView.animate(withDuration: 0.22) {
                    container.frame = CGRect(
                        x: self.panelMargin,
                        y: yTop - self.panelHeight - self.panelMargin,
                        width: window.bounds.width - self.panelMargin * 2,
                        height: self.panelHeight
                    )
                }
            }
        }
    }
    
    // MARK: - Pannello flottante
    
    private func showPanel() {
        guard panelContainer == nil, let window = keyWindow() else { return }
        
        let yTop = keyboardTopY(in: window)
        
        let container = UIView(frame: CGRect(
            x: panelMargin,
            y: yTop - panelHeight - panelMargin,
            width: window.bounds.width - panelMargin * 2,
            height: panelHeight
        ))
        container.backgroundColor = .clear
        
        let panelView = NoteLiquidPanelView(model: model) { [weak self] cmd in
            guard let self, let tv = self.textView else { return }
            RichTextFormatter.toggle(cmd, in: tv)
            self.refreshFromTextView()
        }
        let host = UIHostingController(rootView: panelView)
        host.view.backgroundColor  = .clear
        host.view.isOpaque         = false
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.frame            = container.bounds
        container.addSubview(host.view)
        window.addSubview(container)
        
        container.alpha     = 0
        container.transform = CGAffineTransform(translationX: 0, y: 14)
        UIView.animate(withDuration: 0.28, delay: 0,
                       usingSpringWithDamping: 0.80, initialSpringVelocity: 0,
                       options: .allowUserInteraction) {
            container.alpha     = 1
            container.transform = .identity
        }
        
        panelContainer = container
        panelHost      = host
    }
    
    private func hidePanel() {
        guard let container = panelContainer else { return }
        panelContainer = nil
        panelHost      = nil
        UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseIn) {
            container.alpha     = 0
            container.transform = CGAffineTransform(translationX: 0, y: 8)
        } completion: { _ in
            container.removeFromSuperview()
        }
    }
    
    // ✅ Usa il frame dalla notifica — sempre affidabile
    private func keyboardTopY(in window: UIWindow) -> CGFloat {
        if keyboardFrameInWindow != .zero {
            // La notifica dà il frame in coordinate di schermo
            let converted = window.convert(keyboardFrameInWindow, from: nil)
            return converted.minY
        }
        // Fallback: prova via view hierarchy
        if let host = superview?.superview {
            let y = host.convert(CGPoint.zero, to: window).y
            if y > 0 { return y }
        }
        return window.bounds.height - 336
    }
    
    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    // MARK: - Attach
    
    func attach(to tv: UITextView) {
        textView = tv
        refreshFromTextView()
    }
    
    // MARK: - Refresh stato toolbar
    
    func refreshFromTextView() {
        guard let tv = textView else { return }
        let attr = tv.attributedText ?? NSAttributedString()
        let sel  = tv.selectedRange
        
        if sel.length > 0, attr.length > 0 {
            let safeLoc = max(0, min(sel.location, attr.length - 1))
            let safeLen = max(0, min(sel.length, attr.length - safeLoc))
            let range   = NSRange(location: safeLoc, length: safeLen)
            model.isBold          = rangeHasFontTrait(attr, range: range, trait: .traitBold)
            model.isItalic        = rangeHasFontTrait(attr, range: range, trait: .traitItalic)
            model.isUnderline     = rangeHasAttrNonZero(attr, range: range, key: .underlineStyle)
            model.isStrikethrough = rangeHasAttrNonZero(attr, range: range, key: .strikethroughStyle)
            model.activeList      = listState(attributed: attr, caret: safeLoc)
        } else {
            let font   = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            let traits = font.fontDescriptor.symbolicTraits
            model.isBold          = traits.contains(.traitBold)
            model.isItalic        = traits.contains(.traitItalic)
            model.isUnderline     = ((tv.typingAttributes[.underlineStyle]     as? Int) ?? 0) != 0
            model.isStrikethrough = ((tv.typingAttributes[.strikethroughStyle] as? Int) ?? 0) != 0
            let caret = max(0, min(sel.location, max(0, attr.length - 1)))
            model.activeList = listState(attributed: attr, caret: caret)
        }
    }
    
    // MARK: - Helpers
    
    private func rangeHasFontTrait(_ attr: NSAttributedString, range: NSRange,
                                   trait: UIFontDescriptor.SymbolicTraits) -> Bool {
        var has = true
        attr.enumerateAttribute(.font, in: range) { value, _, stop in
            let f = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            if !f.fontDescriptor.symbolicTraits.contains(trait) { has = false; stop.pointee = true }
        }
        return has
    }
    
    private func rangeHasAttrNonZero(_ attr: NSAttributedString, range: NSRange,
                                     key: NSAttributedString.Key) -> Bool {
        var has = true
        attr.enumerateAttribute(key, in: range) { value, _, stop in
            if ((value as? Int) ?? 0) == 0 { has = false; stop.pointee = true }
        }
        return has
    }
    
    private func listState(attributed: NSAttributedString,
                           caret: Int) -> RichTextToolbarModel.ActiveList {
        guard attributed.length > 0 else { return .none }
        let idx  = max(0, min(caret, attributed.length - 1))
        let ns   = attributed.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
        guard para.length > 0 else { return .none }
        let snip = ns.substring(with: NSRange(location: para.location,
                                              length: min(10, para.length)))
        if snip.hasPrefix("○") || snip.hasPrefix("◉")                     { return .checklist }
        if snip.hasPrefix("•")                                              { return .bullet }
        if snip.range(of: #"^\d+\. "#, options: .regularExpression) != nil { return .number }
        return .none
    }
}
