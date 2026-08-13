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
    /// Store opzionale per Mac Catalyst: registra la UITextView e riflette lo stato
    var store: NoteRichTextStore? = nil
    /// Notificato subito a ogni modifica (anche prima che l'HTML venga serializzato,
    /// che è un'operazione costosa e quindi debounced).
    var onEdit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = RichUITextView()
        tv.isEditable    = true
        tv.isSelectable  = true
        tv.alwaysBounceVertical = true
        tv.backgroundColor      = .clear
        tv.delegate             = context.coordinator
        tv.textContainerInset   = UIEdgeInsets(top: 2, left: 6, bottom: 16, right: 6)
        tv.typingAttributes     = NSAttributedString.defaultTypingAttributes(font: baseFont)
        // ✅ Fondamentale: contentInset bottom sarà aggiornato dinamicamente con la tastiera
        tv.contentInset          = .zero
        tv.scrollIndicatorInsets = .zero
        tv.automaticallyAdjustsScrollIndicatorInsets = false
        // Scorrendo verso il basso la tastiera si abbassa seguendo il dito (come Note/Mail):
        // su note lunghe è il modo più rapido per liberare metà schermo.
        tv.keyboardDismissMode   = .interactive

        tv.onTab = { isShift in
            if isShift { RichTextFormatter.outdentList(in: tv) }
            else        { RichTextFormatter.indentList(in: tv) }
        }
        tv.onPastePlainText = { pasted in
            context.coordinator.handlePastePlainText(pasted, in: tv)
        }
        
        // Traccia l'HTML già presente nella text view: `updateUIView` lo usa come
        // identità per NON ricaricare il testo a ogni re-render di SwiftUI.
        context.coordinator.lastSyncedHTML = html

        if let attr = NSAttributedString.fromHTML(html, fallbackFont: baseFont),
           attr.length > 0 {
            tv.attributedText = attr
        } else if !placeholder.isEmpty {
            tv.text      = placeholder
            tv.textColor = .secondaryLabel
            tv.font      = baseFont
            // Segnala al Coordinator che il testo attuale è il placeholder,
            // così `textViewDidBeginEditing` lo ripulirà al primo focus.
            context.coordinator.isShowingPlaceholder = true
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

        // Registra nel store esterno (Mac Catalyst / salvataggio)
        context.coordinator.bind(store: store, textView: tv)

        // ✅ Keyboard observers per aggiornare contentInset e scrollare il cursore in vista
        context.coordinator.registerKeyboardObservers(for: tv)

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isProgrammaticUpdate = true
        defer { coordinator.isProgrammaticUpdate = false }

        // Aggiorna riferimento store (potrebbe cambiare tra un update e l'altro)
        coordinator.bind(store: store, textView: uiView)

        // Focus richiesto dal titolo (tasto Avanti)
        if let trigger = focusTrigger, trigger != coordinator.lastFocusTrigger {
            coordinator.lastFocusTrigger = trigger
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }

        // Se stiamo mostrando il placeholder e il binding è ancora vuoto, NON
        // sovrascrivere il textStorage: altrimenti cancelleremmo il placeholder
        // visibile e lasceremmo l'editor apparentemente "morto".
        if coordinator.isShowingPlaceholder,
           html.isEmpty {
            return
        }

        // ⚠️ Confronto per *identità della stringa*, non ri-serializzando la text
        //    view. `toHTML()` è costoso (passa da NSAttributedString→HTML) e —
        //    soprattutto — non è mai identico all'HTML salvato lato server /
        //    Android: il confronto falliva sempre e a ogni re-render di SwiftUI
        //    (comparsa tastiera, isDirty, refresh di @Query…) il testo veniva
        //    ricaricato da zero, azzerando scroll e selezione.
        guard html != coordinator.lastSyncedHTML else { return }
        guard let attr = NSAttributedString.fromHTML(html, fallbackFont: baseFont),
              attr.length > 0 else {
            // Binding vuoto / non parsabile: lascia che sia `textViewDidEndEditing`
            // (o il prossimo makeUIView) a installare il placeholder, per non
            // sostituire il contenuto mentre l'utente sta ancora digitando.
            return
        }

        // ⚠️ Importante: siamo in stato "placeholder" solo se il textStorage
        //     contiene il placeholder. Ora stiamo per sovrascrivere con il
        //     contenuto reale: resettiamo il flag, altrimenti il prossimo
        //     `textViewDidBeginEditing` cancellerebbe il testo appena
        //     caricato con `textView.text = ""`.
        coordinator.isShowingPlaceholder = false
        coordinator.lastSyncedHTML = html

        // Preserva selezione e posizione di scroll: un aggiornamento remoto non
        // deve riportare l'utente in cima alla nota.
        let selection = uiView.selectedRange
        let offset    = uiView.contentOffset
        uiView.attributedText = attr
        let length = uiView.attributedText.length
        let loc    = min(selection.location, length)
        uiView.selectedRange = NSRange(location: loc,
                                       length: min(selection.length, length - loc))
        uiView.layoutIfNeeded()
        let minY = -uiView.adjustedContentInset.top
        let maxY = max(minY, uiView.contentSize.height
                       + uiView.adjustedContentInset.bottom
                       - uiView.bounds.height)
        uiView.setContentOffset(CGPoint(x: offset.x,
                                        y: min(max(offset.y, minY), maxY)),
                                animated: false)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let parent: RichTextView
        var isProgrammaticUpdate = false
        var lastFocusTrigger: UUID? = nil
        /// Riferimento allo store esterno (Mac Catalyst)
        weak var store: NoteRichTextStore?
        // ℹ️ Visibile dal `RichTextView` così che `makeUIView` possa marcare lo
        //    stato "placeholder attivo" al primo setup (altrimenti
        //    `textViewDidBeginEditing` non pulisce il testo placeholder e la
        //    checklist inserita tramite toolbar finisce davanti al placeholder
        //    invisibilmente in secondaryLabel).
        var isShowingPlaceholder = false
        /// Ultimo HTML che risulta *già allineato* tra binding e text view.
        /// Serve a evitare sia ricariche inutili del testo sia riscritture del binding.
        var lastSyncedHTML: String? = nil

        private var htmlSyncWorkItem: DispatchWorkItem?
        /// Ritardo con cui l'HTML viene rigenerato dopo una modifica.
        /// `toHTML()` costa decine di ms su note lunghe: farlo a ogni tasto
        /// rendeva la digitazione (e lo scroll) a scatti.
        private let htmlSyncDelay: TimeInterval = 0.35

        init(_ parent: RichTextView) { self.parent = parent }

        deinit { htmlSyncWorkItem?.cancel() }

        // MARK: - Store binding

        func bind(store: NoteRichTextStore?, textView: UITextView) {
            self.store = store
            guard let store else { return }
            store.textView = textView
            store.flushPendingHTML = { [weak self, weak textView] in
                guard let self, let textView else { return nil }
                return self.flushHTML(from: textView)
            }
        }

        // MARK: - Editing lifecycle

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard isShowingPlaceholder else { return }
            isShowingPlaceholder = false
            textView.text = ""
            textView.textColor = .richTextPrimary
            textView.font = parent.baseFont
            textView.typingAttributes = NSAttributedString.defaultTypingAttributes(font: parent.baseFont)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            flushHTML(from: textView)
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
            handleTextChanged(in: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            refreshToolbars(in: textView)
        }

        /// Punto unico per ogni modifica del testo — sia da tastiera sia
        /// programmatica (continuazione liste, paste, comandi toolbar, checklist).
        func handleTextChanged(in textView: UITextView) {
            guard !isShowingPlaceholder else { return }
            parent.onEdit?()
            refreshToolbars(in: textView)
            scheduleHTMLSync(from: textView)
        }

        private func refreshToolbars(in textView: UITextView) {
            (textView.inputAccessoryView as? RichTextAccessoryView)?.refreshFromTextView()
            #if targetEnvironment(macCatalyst)
            // Su iOS lo stato è già riflesso dalla inputAccessoryView: rifarlo
            // anche sullo store raddoppierebbe la scansione degli attributi.
            store?.refreshModel()
            #endif
        }

        // MARK: - Serializzazione HTML (debounced)

        private func scheduleHTMLSync(from textView: UITextView) {
            htmlSyncWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.flushHTML(from: textView)
            }
            htmlSyncWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + htmlSyncDelay, execute: work)
        }

        /// Rigenera subito l'HTML e lo scrive nel binding.
        /// - Returns: l'HTML aggiornato, oppure `nil` se non era cambiato nulla.
        @discardableResult
        func flushHTML(from textView: UITextView) -> String? {
            htmlSyncWorkItem?.cancel()
            htmlSyncWorkItem = nil
            guard !isShowingPlaceholder else { return nil }
            let html = textView.attributedText.toHTML() ?? ""
            guard html != lastSyncedHTML else { return nil }
            lastSyncedHTML = html
            parent.html    = html
            return html
        }

        // MARK: Checklist tap

        @objc func handleChecklistTap(_ gr: UITapGestureRecognizer) {
            guard let tv = gr.view as? UITextView else { return }
            if RichTextFormatter.handleChecklistTap(at: gr.location(in: tv), in: tv) {
                handleTextChanged(in: tv)
            }
        }
        
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        
        // MARK: - shouldChangeText: auto-continue + exit list on Return/Backspace
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // ⚠️ Quando gestiamo noi l'inserimento (return `false`) UIKit non
            //    chiama `textViewDidChange`: senza notifica esplicita la modifica
            //    non finiva mai nel binding e andava persa se l'utente usciva
            //    subito dopo aver premuto Invio in una lista.
            if text == "\n" {
                let allowDefault = handleReturn(textView, range: range)
                if !allowDefault { handleTextChanged(in: textView) }
                return allowDefault
            }
            if text.isEmpty, range.length == 1 {
                let allowDefault = handleBackspace(textView, range: range)
                if !allowDefault { handleTextChanged(in: textView) }
                return allowDefault
            }
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
                    .font: UIFont.systemFont(ofSize: CHECKLIST_CIRCLE_FONT_SIZE),
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
            let offset = tv.contentOffset
            tv.textStorage.setAttributedString(ms)
            tv.selectedRange = NSRange(location: min(prLoc, ms.length), length: 0)
            RichTextFormatter.restoreScroll(offset, in: tv)
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
            
            insertAtCaret(tv, attributed: insertion)
            
            // ✅ Fix: dopo l'inserimento il cursore è dopo "○ ".
            //    Reimposta typingAttributes con il font corpo normale, altrimenti
            //    il testo digitato eredita il font size=20 del cerchio.
            tv.typingAttributes = [
                .font:            parent.baseFont,
                .foregroundColor: UIColor.richTextPrimary,
                .paragraphStyle:  ps
            ]
        }
        
        private func insertAtCaret(_ tv: UITextView, attributed: NSAttributedString) {
            let ms  = NSMutableAttributedString(attributedString: tv.attributedText)
            let sel = tv.selectedRange
            let ns  = ms.string as NSString
            let loc = max(0, min(sel.location, ns.length))
            let len = max(0, min(sel.length, ns.length - loc))
            ms.replaceCharacters(in: NSRange(location: loc, length: len), with: attributed)
            let offset = tv.contentOffset
            tv.textStorage.setAttributedString(ms)
            let newCaret = loc + attributed.length
            tv.selectedRange = NSRange(location: min(newCaret, ms.length), length: 0)
            RichTextFormatter.restoreScroll(offset, in: tv)
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
            let offset = tv.contentOffset
            tv.textStorage.setAttributedString(ms)
            tv.selectedRange = NSRange(location: loc + (pasted as NSString).length, length: 0)
            RichTextFormatter.restoreScroll(offset, in: tv)
            // Il paste è gestito da noi: notifichiamo, altrimenti il testo
            // incollato non arriverebbe mai al binding.
            handleTextChanged(in: tv)
            return true
        }
        
        // MARK: - Keyboard scroll handling
        
        private weak var observedTextView: UITextView?
        private var keyboardOverlap: CGFloat = 0

        func registerKeyboardObservers(for tv: UITextView) {
            observedTextView = tv
            let center = NotificationCenter.default
            // `willChangeFrame` copre comparsa, cambio altezza (emoji, dettatura,
            // tastiera hardware, split) e scomparsa: un solo punto di verità.
            center.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(keyboardWillHide(_:)),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        @objc private func keyboardWillChangeFrame(_ n: Notification) {
            guard let tv = observedTextView,
                  let window = tv.window,
                  let info = n.userInfo,
                  let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else { return }

            // ✅ Il frame arriva in coordinate di schermo: convertiamolo nello spazio
            //    della text view. Così l'inset è esattamente la porzione di editor
            //    coperta — corretto anche su iPad (Split View, Stage Manager,
            //    tastiera flottante) e senza contare due volte la safe area
            //    dell'home indicator, come faceva il calcolo su UIScreen.
            let frameInView = tv.convert(window.convert(endFrame, from: nil), from: window)
            let overlap     = max(0, tv.bounds.maxY - frameInView.minY)
            applyKeyboardOverlap(overlap, info: info)
        }

        @objc private func keyboardWillHide(_ n: Notification) {
            // `force`: la tastiera sparisce comunque, l'inset va azzerato anche se
            // l'utente ha ancora il dito sullo schermo (chiusura interattiva).
            applyKeyboardOverlap(0, info: n.userInfo, force: true)
        }

        /// Riallinea l'inset a fine trascinamento: se nel frattempo la tastiera è
        /// sparita senza che abbiamo potuto aggiornarlo, qui recuperiamo.
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
            guard let tv = observedTextView, scrollView === tv else { return }
            if !tv.isFirstResponder, keyboardOverlap != 0 {
                applyKeyboardOverlap(0, info: nil, force: true)
            }
        }

        private func applyKeyboardOverlap(_ overlap: CGFloat,
                                          info: [AnyHashable: Any]?,
                                          force: Bool = false) {
            guard let tv = observedTextView else { return }
            let duration = (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0

            // Durante la chiusura interattiva (dito sulla tastiera) arrivano
            // notifiche a raffica con duration 0: cambiare l'inset mentre l'utente
            // trascina fa saltare lo scroll. L'inset finale lo mette `willHide`.
            if !force, duration <= 0, tv.isDragging || tv.isTracking { return }

            let previous = keyboardOverlap
            guard abs(previous - overlap) > 0.5 else { return }
            keyboardOverlap = overlap

            let applyInsets = {
                tv.contentInset.bottom                  = overlap
                tv.verticalScrollIndicatorInsets.bottom = overlap
            }
            if duration > 0 {
                let curve = (info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
                UIView.animate(withDuration: duration, delay: 0,
                               options: UIView.AnimationOptions(rawValue: curve << 16),
                               animations: applyInsets)
            } else if force, overlap == 0 {
                // Chiusura senza animazione dichiarata: una dissolvenza breve
                // evita che il fondo della nota "salti".
                UIView.animate(withDuration: 0.2, animations: applyInsets)
            } else {
                applyInsets()
            }

            // Porta il cursore in vista solo se la tastiera lo sta davvero coprendo.
            guard overlap > previous else { return }
            DispatchQueue.main.async { [weak self] in self?.scrollCaretIntoViewIfNeeded() }
        }

        /// Scrolla al cursore **solo** se serve: se è già visibile, o se l'utente
        /// sta scorrendo a mano, non tocchiamo il contentOffset. Prima uno
        /// `scrollRangeToVisible` incondizionato (ritardato) riportava la nota sul
        /// cursore mentre l'utente stava scrollando, sembrando uno scroll bloccato.
        private func scrollCaretIntoViewIfNeeded() {
            guard let tv = observedTextView,
                  tv.isFirstResponder,
                  !tv.isDragging, !tv.isDecelerating,
                  let selection = tv.selectedTextRange
            else { return }

            let caret = tv.caretRect(for: selection.end)
            guard !caret.isNull, caret.height > 0, caret.height < 10_000 else { return }

            let inset   = tv.adjustedContentInset
            let visible = CGRect(x: tv.contentOffset.x,
                                 y: tv.contentOffset.y + inset.top,
                                 width: tv.bounds.width,
                                 height: max(0, tv.bounds.height - inset.top - inset.bottom))
            guard !visible.contains(caret) else { return }
            tv.scrollRectToVisible(caret.insetBy(dx: 0, dy: -12), animated: true)
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

        // 5) Re-styling delle righe checklist: il font grande del cerchio ○/◉
        //    non viene salvato nell'HTML (vedi `toHTML()`), quindi lo rimettiamo
        //    qui al load, insieme al colore giusto e al paragraphStyle con
        //    indent wrapped corretto.
        let ns = raw.string as NSString
        var idx = 0
        while idx < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            guard para.length > 0 else { break }
            let firstChar = ns.substring(with: NSRange(location: para.location, length: 1))
            if firstChar == "○" || firstChar == "◉" {
                let circleRange = NSRange(location: para.location, length: 1)
                raw.addAttribute(.font,
                                 value: UIFont.systemFont(ofSize: CHECKLIST_CIRCLE_FONT_SIZE),
                                 range: circleRange)
                raw.addAttribute(.foregroundColor,
                                 value: firstChar == "◉" ? UIColor.systemGreen
                                                         : UIColor.secondaryLabel,
                                 range: circleRange)

                let ps = NSMutableParagraphStyle()
                applyChecklistParagraphStyle(ps)
                raw.addAttribute(.paragraphStyle, value: ps, range: para)
            }
            let next = para.location + para.length
            if next <= idx { break }
            idx = next
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
        // ⚠️ Strategia simmetrica ad Android: il font grande del cerchio
        //     checklist NON viene serializzato nell'HTML (tanto il sanitizer
        //     cross-platform rimuove `<head><style>` e le `class="…"` con cui
        //     `NSAttributedString.data(...)` esprime il font-size, quindi
        //     finirebbe perso comunque). Al load, `fromHTML` riapplica il
        //     `CHECKLIST_CIRCLE_FONT_SIZE` a ogni `○`/`◉` di inizio riga.
        let cleaned = NSMutableAttributedString(attributedString: self)
        if cleaned.length > 0 {
            let ns = cleaned.string as NSString
            var idx = 0
            while idx < ns.length {
                let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
                if para.length > 0 {
                    let first = ns.substring(with: NSRange(location: para.location, length: 1))
                    if first == "○" || first == "◉" {
                        cleaned.removeAttribute(.font,
                                                range: NSRange(location: para.location, length: 1))
                    }
                }
                let next = para.location + para.length
                if next <= idx { break }
                idx = next
            }
        }

        let options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let data = try? cleaned.data(from: NSRange(location: 0, length: cleaned.length),
                                           documentAttributes: options),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        // Rendi l'HTML cross-platform: rimuovi <head>/<style>/class="..."
        // così che Android (HtmlCompat.fromHtml) possa renderizzarlo senza
        // mostrare il CSS come testo. I tag base (b/i/u/p/br/ul/li/span style…)
        // rimangono, così il rendering è equivalente anche su iOS.
        return NoteHtmlSanitizer.sanitizeCrossPlatform(raw)
    }
}
